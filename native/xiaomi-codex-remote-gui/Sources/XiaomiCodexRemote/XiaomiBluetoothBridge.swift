import CoreBluetooth
import Foundation

public final class XiaomiBluetoothBridge: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var txChar: CBCharacteristic?
    private var rxChar: CBCharacteristic?
    private var ctlChar: CBCharacteristic?

    private var capabilities: ATVVCapabilities?
    private var decoder = IMAADPCMDecoder()
    private var accumulator = FrameAccumulator()
    private var pendingSync: (predictor: Int, stepIndex: Int)?
    private var isStreaming = false
    private var isMicOpened = false
    private var receivedAudioPackets = 0
    private var decodedSamples = 0
    private var peakSample = 0

    public let audioOutput: VirtualAudioOutput
    public var gainDB: Double = 6.0 // Default +6dB gain for clear microphone level

    public var onStateChange: ((String) -> Void)?
    public var onBatteryUpdate: ((Int) -> Void)?
    public var onVoiceStart: (() -> Void)?
    public var onVoiceStop: (() -> Void)?

    public private(set) var remoteName: String?
    public private(set) var batteryLevel: Int?

    public init(audioOutput: VirtualAudioOutput) {
        self.audioOutput = audioOutput
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[BLE] Bluetooth powered on. Discovering remote...")
            onStateChange?("正在搜索遥控器...")
            connectToRemote()
        case .poweredOff:
            onStateChange?("蓝牙未开启")
        case .unauthorized:
            onStateChange?("蓝牙权限未授权")
        default:
            onStateChange?("蓝牙不可用")
        }
    }

    private func connectToRemote() {
        let serviceUUID = CBUUID(string: ATVVProtocol.serviceUUID)
        let hidUUID = CBUUID(string: "1812")

        let connected = central.retrieveConnectedPeripherals(withServices: [serviceUUID, hidUUID])
        for p in connected {
            let name = p.name ?? ""
            if isTargetRemoteName(name) {
                print("[BLE] Found connected Xiaomi remote: \(name) [\(p.identifier)]")
                attachPeripheral(p)
                return
            }
        }

        print("[BLE] Remote not in connected list, scanning...")
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    private func isTargetRemoteName(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n.contains("mi rc") || n.contains("xiaomi") || n.contains("rc003") || n.contains("遥控器")
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        if isTargetRemoteName(name) {
            print("[BLE] Discovered target remote: \(name)")
            central.stopScan()
            attachPeripheral(peripheral)
        }
    }

    private func attachPeripheral(_ p: CBPeripheral) {
        self.peripheral = p
        self.remoteName = p.name ?? "小米蓝牙语音遥控器"
        p.delegate = self
        onStateChange?("正在连接 \(remoteName!)...")
        central.connect(p, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BLE] Connected to: \(peripheral.name ?? "Unknown")")
        onStateChange?("已连接，正在初始化语音服务...")
        peripheral.discoverServices([
            CBUUID(string: ATVVProtocol.serviceUUID),
            CBUUID(string: "180F"), // Battery
            CBUUID(string: "180A"), // Device Information
        ])
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[BLE] Disconnected from remote: \(error?.localizedDescription ?? "Normal")")
        stopStreaming()
        onStateChange?("已断开连接，正在重连...")
        self.peripheral = nil
        self.txChar = nil
        self.rxChar = nil
        self.ctlChar = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.central.state == .poweredOn {
                self.connectToRemote()
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for s in services {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            if c.uuid == CBUUID(string: ATVVProtocol.transmitUUID) {
                txChar = c
            } else if c.uuid == CBUUID(string: ATVVProtocol.audioUUID) {
                rxChar = c
                peripheral.setNotifyValue(true, for: c)
            } else if c.uuid == CBUUID(string: ATVVProtocol.controlUUID) {
                ctlChar = c
                peripheral.setNotifyValue(true, for: c)
            } else if c.uuid == CBUUID(string: "2A19") { // Battery Level
                peripheral.setNotifyValue(true, for: c)
                peripheral.readValue(for: c)
            }
        }

        // When ATVV chars are discovered, request capabilities
        if txChar != nil && rxChar != nil && ctlChar != nil {
            print("[BLE] ATVV voice characteristics ready. Requesting capabilities...")
            onStateChange?("已连接: \(remoteName ?? "遥控器")")
            sendGetCaps()
        }
    }

    private func sendGetCaps() {
        guard let tx = txChar, let p = peripheral else { return }
        let writeType: CBCharacteristicWriteType = tx.properties.contains(.write) ? .withResponse : .withoutResponse
        p.writeValue(ATVVProtocol.getCapabilitiesV10, for: tx, type: writeType)
    }

    @discardableResult
    public func requestMicrophoneOpen() -> Bool {
        guard let tx = txChar, let p = peripheral else {
            onStateChange?("语音打开失败：BLE 语音特征尚未就绪")
            return false
        }
        guard !isMicOpened else {
            onStateChange?("语音打开请求被忽略：已有打开中的会话")
            return false
        }
        receivedAudioPackets = 0
        decodedSamples = 0
        peakSample = 0
        onStateChange?("发送麦克风 OPEN；音频订阅=\(rxChar?.isNotifying == true)，控制订阅=\(ctlChar?.isNotifying == true)，声卡就绪=\(audioOutput.isReady)")
        print("[BLE] Requesting microphone OPEN...")
        isMicOpened = true
        let version = capabilities?.version ?? 0x0004
        let codec = capabilities?.selectedCodec ?? 0x02
        let writeType: CBCharacteristicWriteType = tx.properties.contains(.write) ? .withResponse : .withoutResponse
        p.writeValue(ATVVProtocol.microphoneOpen(version: version, codec: codec), for: tx, type: writeType)
        return true
    }

    public func closeMicrophone() {
        guard let tx = txChar, let p = peripheral, isMicOpened else { return }
        print("[BLE] Requesting microphone CLOSE...")
        isMicOpened = false
        let version = capabilities?.version ?? 0x0004
        let writeType: CBCharacteristicWriteType = tx.properties.contains(.write) ? .withResponse : .withoutResponse
        p.writeValue(ATVVProtocol.microphoneClose(version: version, sessionID: 0), for: tx, type: writeType)
        stopStreaming()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            onStateChange?("BLE 通知错误 \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }

        if characteristic.uuid == CBUUID(string: "2A19") {
            if let level = data.first {
                self.batteryLevel = Int(level)
                print("[BLE] Battery Level: \(level)%")
                onBatteryUpdate?(Int(level))
            }
            return
        }

        if characteristic.uuid == CBUUID(string: ATVVProtocol.controlUUID) {
            handleControl(data)
        } else if characteristic.uuid == CBUUID(string: ATVVProtocol.audioUUID) {
            handleAudio(data)
        }
    }

    private func handleControl(_ data: Data) {
        guard let opcode = data.first else { return }
        if opcode != 0x0A {
            onStateChange?("ATVV 控制: " + data.prefix(24).map { String(format: "%02x", $0) }.joined(separator: " "))
        }

        switch opcode {
        case 0x0B: // CAPS_RESP
            if let caps = ATVVCapabilities.parse(data) {
                self.capabilities = caps
                onStateChange?("语音能力：版本=\(caps.version)，codec=\(caps.selectedCodec)，采样率=\(caps.sampleRate)，帧长=\(caps.frameSize)")
                print("[ATVV] Caps parsed: version=0x\(String(caps.version, radix: 16)), codec=\(caps.selectedCodec), rate=\(caps.sampleRate)")
            }
        case 0x08: // SEARCH (Voice button pressed on remote)
            print("[ATVV] Remote triggered voice search (0x08)")
            _ = requestMicrophoneOpen()
            onVoiceStart?()
        case 0x04: // AUDIO_START
            print("[ATVV] Remote started audio stream (0x04)")
            startStreaming()
        case 0x00: // AUDIO_STOP
            print("[ATVV] Remote stopped audio stream (0x00)")
            stopStreaming()
            onVoiceStop?()
        case 0x0A: // SYNC
            if data.count >= 7 {
                let predRaw = (Int(data[4]) << 8) | Int(data[5])
                let pred = predRaw >= 0x8000 ? predRaw - 0x10000 : predRaw
                let idx = Int(data[6])
                self.pendingSync = (pred, idx)
            }
        default:
            break
        }
    }

    private func startStreaming() {
        receivedAudioPackets = 0
        decodedSamples = 0
        peakSample = 0
        onStateChange?("收到 AUDIO_START，开始接收音频")
        accumulator.reset()
        pendingSync = nil
        decoder.reset()
        isStreaming = true
        print("[ATVV] Streaming started")
    }

    private func stopStreaming() {
        guard isStreaming else { return }
        onStateChange?("语音统计：收到 \(receivedAudioPackets) 包，解码 \(decodedSamples) 样本，PCM峰值 \(peakSample)；\(audioOutput.diagnosticStatus)")
        isStreaming = false
        isMicOpened = false
        accumulator.reset()
        pendingSync = nil
        print("[ATVV] Streaming stopped")
    }

    private func handleAudio(_ data: Data) {
        receivedAudioPackets += 1
        if receivedAudioPackets == 1 {
            onStateChange?("收到首个音频包：\(data.count) 字节；流已启动=\(isStreaming)")
        }
        guard isStreaming else { return }

        let frameSize = capabilities?.frameSize ?? 120
        let frames = accumulator.append(data, frameSize: frameSize)

        for frame in frames {
            if let sync = pendingSync {
                decoder.reset(predictor: sync.predictor, stepIndex: sync.stepIndex)
                pendingSync = nil
            }
            let decoded = decoder.decode(frame)
            let processed = PCMPostprocessor.process(decoded, gainDB: gainDB)
            let isFirstFrame = decodedSamples == 0
            decodedSamples += processed.count
            peakSample = max(peakSample, processed.map { abs(Int($0)) }.max() ?? 0)
            audioOutput.enqueue(samples: processed)
            if isFirstFrame {
                onStateChange?("首帧解码：\(processed.count) 样本，PCM峰值 \(peakSample)；\(audioOutput.diagnosticStatus)")
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        onStateChange?("BLE 订阅 \(characteristic.uuid): \(characteristic.isNotifying)，错误=\(error?.localizedDescription ?? "无")")
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        onStateChange?("BLE 写入 \(characteristic.uuid): \(error?.localizedDescription ?? "成功")")
    }
}
