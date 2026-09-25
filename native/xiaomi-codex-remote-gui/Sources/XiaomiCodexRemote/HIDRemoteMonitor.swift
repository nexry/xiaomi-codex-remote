import Foundation
import IOKit.hid

public final class HIDRemoteMonitor {
    private struct RegisteredDevice {
        let device: IOHIDDevice
        let buffer: UnsafeMutablePointer<UInt8>
    }

    private var manager: IOHIDManager?
    private var registeredDevices: [RegisteredDevice] = []
    private let bufferSize = 256
    private var pressedKey: String?
    private let accessProvider: HIDAccessProviding
    private var requestedAccess = false
    private(set) var isMonitoring = false
    var onStatus: ((HIDMonitorStatus) -> Void)?

    public var onButtonEvent: ((_ key: String, _ action: String) -> Void)?
    public var onDeviceStatus: ((_ connected: Bool) -> Void)?

    private static let keyMap: [UInt8: String] = [
        0x28: "ok",
        0x52: "up",
        0x51: "down",
        0x50: "left",
        0x4f: "right",
        0x4a: "home",
        0xf1: "back",
        0x65: "menu",
        0x80: "volume_up",
        0x81: "volume_down",
        0x3e: "voice",
        0x66: "power",
    ]

    public convenience init() { self.init(accessProvider: SystemHIDAccessProvider()) }
    init(accessProvider: HIDAccessProviding) { self.accessProvider = accessProvider }

    deinit {
        stop()
    }

    public func start() {
        guard manager == nil else { return }
        if accessProvider.status == .unknown, !requestedAccess {
            requestedAccess = true
            _ = accessProvider.request()
        }
        switch accessProvider.status {
        case .denied: onStatus?(.permissionDenied); return
        case .unknown: onStatus?(.permissionRequired); return
        case .granted: break
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x2717,
            kIOHIDProductIDKey: 0x32B8,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context else { return }
            let monitor = Unmanaged<HIDRemoteMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.deviceMatched(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context else { return }
            let monitor = Unmanaged<HIDRemoteMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.deviceRemoved(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            stop()
            onStatus?(.failed("IOHIDManager: \(openResult)"))
            print("[HID] Failed to open IOHIDManager: \(openResult)")
        } else {
            isMonitoring = true
            onStatus?(.searching)
            print("[HID] IOHIDManager monitoring Xiaomi RC003 HID reports")
        }
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        if registeredDevices.contains(where: { $0.device == device }) { return }

        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Xiaomi Remote"
        print("[HID] Xiaomi RC003 matched: \(name)")

        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        buf.initialize(repeating: 0, count: bufferSize)
        registeredDevices.append(RegisteredDevice(device: device, buffer: buf))

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputReportCallback(device, buf, bufferSize, { context, result, sender, type, reportID, report, reportLength in
            guard let context, result == kIOReturnSuccess, reportLength > 0 else { return }
            let monitor = Unmanaged<HIDRemoteMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleInputReport(reportID: reportID, report: report, length: reportLength)
        }, context)

        onDeviceStatus?(true)
        onStatus?(.connected(name: name))
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        if let idx = registeredDevices.firstIndex(where: { $0.device == device }) {
            let reg = registeredDevices.remove(at: idx)
            reg.buffer.deallocate()
        }
        if registeredDevices.isEmpty {
            releaseHeldButton()
            print("[HID] Xiaomi RC003 disconnected")
            onDeviceStatus?(false)
            onStatus?(.searching)
        }
    }

    private func handleInputReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        let count = Int(length)
        guard count >= 3 else { return }
        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            bytes[i] = report[i]
        }

        // Standard keyboard input report for RC003:
        // [0]: reportId (1)
        // [1]: modifier (0)
        // [2]: reserved (0)
        // [3..n]: keycodes
        var keyBytes: [UInt8] = []
        if bytes[0] == 1 && count >= 4 {
            keyBytes = Array(bytes[3...])
        } else if count >= 3 {
            keyBytes = Array(bytes[2...])
        } else {
            return
        }

        var activeKey: String?
        for code in keyBytes {
            if code != 0, let name = Self.keyMap[code] {
                activeKey = name
                break
            }
        }

        if let keyName = activeKey {
            if pressedKey == keyName {
                onButtonEvent?(keyName, "repeat")
            } else {
                releaseHeldButton()
                pressedKey = keyName
                onButtonEvent?(keyName, "press")
            }
        } else {
            // All keys released
            releaseHeldButton()
        }
    }

    public func releaseHeldButton() {
        if let key = pressedKey {
            pressedKey = nil
            onButtonEvent?(key, "release")
        }
    }

    public func stop() {
        releaseHeldButton()
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            self.manager = nil
        }
        for reg in registeredDevices {
            reg.buffer.deallocate()
        }
        registeredDevices.removeAll()
        isMonitoring = false
        onDeviceStatus?(false)
        onStatus?(.stopped)
    }
}
