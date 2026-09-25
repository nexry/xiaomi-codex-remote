import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import AudioExceptionGuard

public struct AudioDeviceInfo: Identifiable, Equatable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
}

public enum CoreAudioDeviceCatalog {
    public static func outputDevices() -> [AudioDeviceInfo] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else { return [] }

        var results: [AudioDeviceInfo] = []
        for id in deviceIDs {
            // Check output stream
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize) == noErr, streamSize > 0 else {
                continue
            }

            // Get UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidCF: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            withUnsafeMutablePointer(to: &uidCF) { ptr in
                _ = AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, ptr)
            }

            // Get Name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameCF: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            withUnsafeMutablePointer(to: &nameCF) { ptr in
                _ = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, ptr)
            }

            results.append(AudioDeviceInfo(id: id, uid: uidCF as String, name: nameCF as String))
        }
        return results
    }

    public static func preferredVirtualDevice() -> AudioDeviceInfo? {
        let devices = outputDevices()
        if let miCodex = devices.first(where: { $0.uid == "MiCodexRemote_UID" || $0.name.contains("MiCodexRemote") }) {
            return miCodex
        }
        if let mi = devices.first(where: { $0.uid == "MiRemoteV2ch_UID" || $0.name.contains("MiRemoteV") }) {
            return mi
        }
        if let bh = devices.first(where: { $0.uid.contains("BlackHole") || $0.name.contains("BlackHole") }) {
            return bh
        }
        return nil
    }

    // MARK: - Virtual Device Audibility Repair

    private static let minimumUsableVolume: Float32 = 0.2

    /// Ensures the virtual audio device is not muted and has adequate volume on
    /// both output and input scopes.  MiRemoteV 2ch (BlackHole-based) is a
    /// loopback driver: audio written to its output scope appears on its input
    /// scope.  macOS may silently mute or zero-out either scope when switching
    /// default devices.  Returns a diagnostic string summarising what was
    /// repaired.
    @discardableResult
    public static func ensureDeviceAudible(_ device: AudioDeviceInfo) -> String {
        let scopes: [(String, AudioObjectPropertyScope)] = [
            ("output", kAudioDevicePropertyScopeOutput),
            ("input",  kAudioDevicePropertyScopeInput),
        ]
        var actions: [String] = []
        for (label, scope) in scopes {
            // Unmute if needed
            if let muted = getUInt32(device.id, selector: kAudioDevicePropertyMute, scope: scope), muted != 0 {
                if setUInt32(device.id, selector: kAudioDevicePropertyMute, scope: scope, value: 0) {
                    actions.append("\(label)_unmuted")
                } else {
                    actions.append("\(label)_unmute_failed")
                }
            }
            // Restore volume if too low
            if let vol = getFloat32(device.id, selector: kAudioDevicePropertyVolumeScalar, scope: scope),
               vol < minimumUsableVolume {
                if setFloat32(device.id, selector: kAudioDevicePropertyVolumeScalar, scope: scope, value: 1.0) {
                    actions.append("\(label)_volume_restored(\(vol)->1.0)")
                } else {
                    actions.append("\(label)_volume_restore_failed(\(vol))")
                }
            }
        }
        let summary = actions.isEmpty ? "audibility_ok" : actions.joined(separator: ",")
        return summary
    }

    /// Returns the AudioDeviceID currently bound to an AudioUnit's output, or
    /// nil if the query fails.
    public static func currentDeviceID(for audioUnit: AudioUnit) -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            &size
        )
        return status == noErr ? deviceID : nil
    }

    // MARK: - CoreAudio property helpers

    private static func getUInt32(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func setUInt32(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        value: UInt32
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(objectID, &address),
              AudioObjectIsPropertySettable(objectID, &address, &settable) == noErr,
              settable.boolValue else { return false }
        var mutableValue = value
        return AudioObjectSetPropertyData(
            objectID, &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &mutableValue
        ) == noErr
    }

    private static func getFloat32(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func setFloat32(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        value: Float32
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(objectID, &address),
              AudioObjectIsPropertySettable(objectID, &address, &settable) == noErr,
              settable.boolValue else { return false }
        var mutableValue = value
        return AudioObjectSetPropertyData(
            objectID, &address, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &mutableValue
        ) == noErr
    }
}

public final class VirtualAudioOutput {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var configurationObserver: NSObjectProtocol?
    private var recovery = AudioPlaybackRecovery()
    public var onStateChange: ((_ ready: Bool, _ message: String) -> Void)?
    private let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    public private(set) var selectedDevice: AudioDeviceInfo?
    public var isReady: Bool {
        selectedDevice != nil && engine?.isRunning == true && player?.isPlaying == true && boundToSelectedDevice
    }

    /// Whether the engine's output AudioUnit is still bound to `selectedDevice`.
    private var boundToSelectedDevice: Bool {
        guard let device = selectedDevice,
              let unit = engine?.outputNode.audioUnit,
              let currentID = CoreAudioDeviceCatalog.currentDeviceID(for: unit) else {
            return selectedDevice == nil  // no device selected = vacuously true
        }
        return currentID == device.id
    }

    public var diagnosticStatus: String {
        "声卡=\(selectedDevice?.name ?? "未选择")，就绪=\(isReady)，引擎运行=\(engine?.isRunning == true)，播放器运行=\(player?.isPlaying == true)，设备绑定=\(boundToSelectedDevice)"
    }

    public init() {}

    @discardableResult
    public func configure(device: AudioDeviceInfo? = nil) -> Bool {
        stop()

        guard let targetDevice = device ?? CoreAudioDeviceCatalog.preferredVirtualDevice() else {
            print("[AUDIO] No suitable virtual audio output device found (MiCodexRemote or BlackHole)")
            return false
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        guard let outputUnit = engine.outputNode.audioUnit else {
            print("[AUDIO] Failed to get output audio unit")
            return false
        }

        var deviceID = targetDevice.id
        let result = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard result == noErr else {
            print("[AUDIO] Failed to set current device ID: \(result)")
            return false
        }

        // Ensure the virtual device is not muted and has adequate volume on
        // both output and input scopes (critical for MiRemoteV 2ch loopback).
        let audibilityResult = CoreAudioDeviceCatalog.ensureDeviceAudible(targetDevice)
        print("[AUDIO] Audibility repair: \(audibilityResult)")

        // Bind the output device before constructing the mixer connection.
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: sourceFormat)

        do {
            engine.prepare()
            try engine.start()
            guard RemoteMicTryPlayAudioPlayerNode(player) else {
                player.stop()
                engine.stop()
                print("[AUDIO] Player node play() failed")
                return false
            }

            self.engine = engine
            self.player = player
            self.selectedDevice = targetDevice
            recovery.onFailure = { [weak self] message in
                self?.onStateChange?(false, "音频恢复失败：\(message)")
            }
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] notification in
                guard let self, let changed = notification.object as? AVAudioEngine,
                      self.engine === changed else { return }
                self.onStateChange?(self.isReady, "音频配置发生变化，检查引擎状态")
                _ = self.resumeIfNeeded()
            }
            onStateChange?(isReady, "音频输出已配置：\(targetDevice.name)")
            print("[AUDIO] Audio output ready, target device: \(targetDevice.name) [\(targetDevice.uid)]")
            return true
        } catch {
            print("[AUDIO] Audio engine start error: \(error)")
            return false
        }
    }

    public func enqueue(samples: [Int16]) {
        guard !samples.isEmpty, resumeIfNeeded(), let player else { return }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.floatChannelData?[0] else { return }

        for i in samples.indices {
            channel[i] = Float(samples[i]) / 32768.0
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    public func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        recovery = AudioPlaybackRecovery()
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        selectedDevice = nil
        onStateChange?(false, "音频输出已停止")
    }

    @discardableResult
    private func resumeIfNeeded() -> Bool {
        guard let engine, let player, let device = selectedDevice else { return false }
        return recovery.ensureRunning(isRunning: { self.isReady }) {
            // Drop queued buffers from the stopped engine to avoid stale voice playback.
            player.stop()
            // Re-check audibility in case macOS reset mute/volume during the interruption.
            let audibilityResult = CoreAudioDeviceCatalog.ensureDeviceAudible(device)
            if audibilityResult != "audibility_ok" {
                print("[AUDIO] Resume audibility repair: \(audibilityResult)")
            }
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            guard RemoteMicTryPlayAudioPlayerNode(player) else {
                throw NSError(domain: "XiaomiCodexRemote.Audio", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "无法启动音频播放器"])
            }
            if self.isReady {
                self.onStateChange?(true, "音频引擎已恢复：\(self.selectedDevice?.name ?? "")")
            }
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        player?.stop()
        engine?.stop()
    }
}
