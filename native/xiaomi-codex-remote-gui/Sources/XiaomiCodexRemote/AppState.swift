import Foundation
import AppKit
import AVFoundation
import CoreBluetooth

/// A single log entry displayed in the unified log view.
struct LogLine: Identifiable {
    let id: UInt64
    let timestamp: Date
    let source: String   // "bridge", "button", "hid", "ble", "atvv", "audio", "app", "chatgpt"
    let text: String
}

/// Centralized observable state for the entire XiaomiCodexRemote application.
/// All subsystem callbacks funnel into this object, which SwiftUI views observe.
@Observable
final class AppState {
    // Subsystems
    let bridge = NativeCodexBridge()
    let chatGPTLauncher = ChatGPTLauncher()
    let hidMonitor = HIDRemoteMonitor()
    let bluetoothBridge: XiaomiBluetoothBridge
    let audioOutput = VirtualAudioOutput()
    let volumeInterceptor = VolumeKeyInterceptor()
    let driverManager = DriverManager()

    // Remote status
    var remoteConnected: Bool = false
    var remoteBattery: Int?
    var remoteName: String?
    var hidStatus: HIDMonitorStatus = .stopped
    var keyMapping: [String: XiaomiBinding?] = AppPreferences.keyMapping()

    // System permissions shown in the main window. Refresh when returning from Settings.
    var bluetoothAuthorization: CBManagerAuthorization = CBManager.authorization
    var inputMonitoringAccess: HIDAccessStatus = SystemHIDAccessProvider().status
    var accessibilityGranted: Bool = false
    var microphoneAuthorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    // Audio status
    var audioReady: Bool = false
    var isVoiceStreaming: Bool = false

    // Unified log
    var logLines: [LogLine] = []
    private var logCounter: UInt64 = 0
    private let maxLogLines = 500

    init() {
        bluetoothBridge = XiaomiBluetoothBridge(audioOutput: audioOutput)
        bridge.applyKeyMapping(keyMapping)
        setupSubsystems()
        refreshPermissions()
    }

    // MARK: - Setup

    private func setupSubsystems() {
        // Audio — request permission once upfront, then configure the engine.
        audioOutput.onStateChange = { [weak self] ready, message in
            self?.audioReady = ready
            self?.appendLog(source: "audio", text: message)
        }
        requestAudioPermissionAndConfigure()

        // HID button events
        hidMonitor.onButtonEvent = { [weak self] key, action in
            guard let self else { return }
            if key == "volume_up" || key == "volume_down" {
                self.volumeInterceptor.suppressNext(duration: 0.35)
            }
            // IOHID is scheduled on the main run loop. Deliver synchronously
            // so stop/disconnect releases cannot arrive after a restart.
            self.handleButton(key: key, action: action)
        }
        hidMonitor.onDeviceStatus = { [weak self] connected in
            self?.remoteConnected = connected
            if !connected { self?.bridge.releaseHeldKeys() }
            self?.appendLog(source: "hid", text: connected ? "遥控器 HID 已连接" : "遥控器 HID 已断开")
        }
        hidMonitor.onStatus = { [weak self] status in
            self?.hidStatus = status
            if case let .connected(name) = status { self?.remoteName = name }
        }

        // Bluetooth bridge
        bluetoothBridge.onStateChange = { [weak self] stateMsg in
            DispatchQueue.main.async {
                self?.appendLog(source: "ble", text: stateMsg)
            }
        }
        bluetoothBridge.onBatteryUpdate = { [weak self] level in
            DispatchQueue.main.async {
                self?.remoteBattery = level
            }
        }
        bluetoothBridge.onVoiceStart = { [weak self] in
            DispatchQueue.main.async {
                self?.isVoiceStreaming = true
                self?.appendLog(source: "atvv", text: "语音流开始")
            }
        }
        bluetoothBridge.onVoiceStop = { [weak self] in
            DispatchQueue.main.async {
                self?.isVoiceStreaming = false
                self?.appendLog(source: "atvv", text: "语音流结束")
            }
        }

        // Native bridge log
        bridge.onLogLine = { [weak self] text in
            self?.appendLog(source: "bridge", text: text)
        }
        bridge.onShimConnectionChange = { [weak self] connected in
            self?.chatGPTLauncher.shimConnectionChanged(connected)
            if connected {
                self?.appendLog(source: "chatgpt", text: "ChatGPT Shim 已连接，兼容副本注入成功")
            }
        }
    }

    // MARK: - Audio Permission

    /// Request microphone permission once at startup. macOS will show the
    /// dialog exactly once; subsequent calls are no-ops. Only after the user
    /// responds do we configure AVAudioEngine, which avoids the repeated
    /// system prompts that occur when the engine starts without prior
    /// authorization.
    private func requestAudioPermissionAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            _ = audioOutput.configure()
            audioReady = audioOutput.isReady
        case .notDetermined:
            appendLog(source: "audio", text: "正在请求麦克风权限...")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.refreshPermissions()
                    if granted {
                        self?.appendLog(source: "audio", text: "麦克风权限已授予")
                        _ = self?.audioOutput.configure()
                        self?.audioReady = self?.audioOutput.isReady ?? false
                    } else {
                        self?.appendLog(source: "audio", text: "麦克风权限被拒绝，语音功能不可用")
                    }
                }
            }
        case .denied, .restricted:
            appendLog(source: "audio", text: "麦克风权限被拒绝，请在系统设置中授予")
        @unknown default:
            _ = audioOutput.configure()
            audioReady = audioOutput.isReady
        }
    }

    func refreshPermissions() {
        bluetoothAuthorization = CBManager.authorization
        inputMonitoringAccess = SystemHIDAccessProvider().status
        accessibilityGranted = volumeInterceptor.checkAccessibility()
        microphoneAuthorization = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func requestInputMonitoringPermission() {
        if inputMonitoringAccess == .denied {
            openPrivacySettings("Privacy_ListenEvent")
            return
        }
        _ = SystemHIDAccessProvider().request()
        refreshPermissions()
        if !hidMonitor.isMonitoring {
            hidMonitor.start()
        }
    }

    func requestAccessibilityPermission() {
        volumeInterceptor.requestAccessibility()
        refreshPermissions()
    }

    func requestMicrophonePermission() {
        if microphoneAuthorization == .notDetermined {
            requestAudioPermissionAndConfigure()
            refreshPermissions()
        } else {
            openPrivacySettings("Privacy_Microphone")
        }
    }

    func openBluetoothPrivacySettings() {
        openPrivacySettings("Privacy_Bluetooth")
    }

    func openAccessibilitySettings() {
        openPrivacySettings("Privacy_Accessibility")
    }

    func refreshAfterReturningToApp() {
        refreshPermissions()
        chatGPTLauncher.refreshCompatibility()
        if inputMonitoringAccess != .granted && hidMonitor.isMonitoring {
            hidMonitor.stop()
        }
        if !hidMonitor.isMonitoring {
            hidMonitor.start()
        }
        if !accessibilityGranted && volumeInterceptor.isEnabled {
            volumeInterceptor.stop()
        }
        if accessibilityGranted && !volumeInterceptor.isEnabled {
            volumeInterceptor.start()
        }
    }

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Actions

    func startAll() {
        bridge.start()
        chatGPTLauncher.refreshCompatibility()
        volumeInterceptor.start()
        hidMonitor.start()

        // Log driver status
        switch driverManager.status {
        case .installed:
            appendLog(source: "audio", text: "MiCodexRemote 驱动已安装")
        case .notInstalled:
            appendLog(source: "audio", text: "MiCodexRemote 驱动未安装，请点击安装")
        default:
            break
        }

        appendLog(source: "app", text: "Xiaomi Codex Remote 启动")
    }

    func stopAll() {
        volumeInterceptor.stop()
        hidMonitor.releaseHeldButton()
        hidMonitor.stop()
        bluetoothBridge.closeMicrophone()
        audioOutput.stop()
        bridge.stop()
    }

    func launchChatGPT() {
        guard bridge.state == .running else {
            appendLog(source: "chatgpt", text: "请先启动桥接服务")
            return
        }
        guard case .ready = chatGPTLauncher.compatibilityState else {
            appendLog(source: "chatgpt", text: "请先准备或修复 ChatGPT 兼容副本")
            return
        }
        appendLog(source: "chatgpt", text: "正在启动 ChatGPT...")
        chatGPTLauncher.launch(socketPath: bridge.socketPath) { [weak self] result in
            switch result {
            case .success:
                self?.appendLog(source: "chatgpt", text: "ChatGPT 已打开，正在等待 Shim 连接")
            case let .failure(error):
                self?.appendLog(source: "chatgpt", text: "ChatGPT 启动失败：\(error.localizedDescription)")
            }
        }
    }

    func prepareChatGPTCompatibility() {
        appendLog(source: "chatgpt", text: "正在准备 ChatGPT 兼容副本，这可能需要一些时间...")
        chatGPTLauncher.prepareCompatibility { [weak self] result in
            switch result {
            case .success:
                self?.appendLog(source: "chatgpt", text: "ChatGPT 兼容副本已准备完成")
            case let .failure(error):
                self?.appendLog(source: "chatgpt", text: "兼容副本准备失败：\(error.localizedDescription)")
            }
        }
    }

    func revealChatGPTDockEntry() {
        chatGPTLauncher.revealDockEntry()
        appendLog(source: "chatgpt", text: "已在 Finder 中显示 ChatGPT Shim，可将它拖到 Dock")
    }

    func installDriver() {
        appendLog(source: "audio", text: "正在安装 MiCodexRemote 驱动...")
        driverManager.install { [weak self] ok, message in
            guard let self else { return }
            if ok {
                self.appendLog(source: "audio", text: "驱动安装成功，正在配置音频...")
                // Re-configure audio output now that the driver is available
                _ = self.audioOutput.configure()
                self.audioReady = self.audioOutput.isReady
            } else {
                self.appendLog(source: "audio", text: "驱动安装失败: \(message)")
            }
        }
    }

    func saveKeyMapping(_ mapping: [String: XiaomiBinding?]) throws {
        let validated = try XiaomiKeyMapping.make(overrides: mapping)
        try AppPreferences.saveKeyMapping(validated)
        bridge.applyKeyMapping(validated)
        keyMapping = validated
        appendLog(source: "app", text: "键位映射已更新")
    }

    func restoreDefaultKeyMapping() {
        AppPreferences.resetKeyMapping()
        bridge.applyKeyMapping(XiaomiKeyMapping.defaults)
        keyMapping = XiaomiKeyMapping.defaults
        appendLog(source: "app", text: "键位映射已恢复默认")
    }

    // MARK: - Button Handling

    private func handleButton(key: String, action: String) {
        print("[BUTTON] \(key) \(action)")
        appendLog(source: "button", text: "\(key) \(action)")

        // Voice microphone coordination
        if key == "voice" {
            if action == "press" {
                _ = bluetoothBridge.requestMicrophoneOpen()
            } else if action == "release" {
                bluetoothBridge.closeMicrophone()
            }
        }

        // Forward to bridge
        guard let parsedAction = XiaomiKeyAction(rawValue: action) else { return }
        bridge.handle(key: key, action: parsedAction)
    }

    func openInputMonitoringSettings() {
        openPrivacySettings("Privacy_ListenEvent")
    }

    // MARK: - Logging

    func appendLog(source: String, text: String) {
        logCounter += 1
        let line = LogLine(id: logCounter, timestamp: Date(), source: source, text: text)
        logLines.append(line)
        if logLines.count > maxLogLines {
            logLines.removeFirst(logLines.count - maxLogLines)
        }
    }
}
