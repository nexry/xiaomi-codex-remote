import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import IOKit.hidsystem

/// Intercepts and suppresses macOS system volume changes caused by Xiaomi Remote buttons.
/// Uses CGEventTap to drop NX_KEYTYPE_SOUND_UP / NX_KEYTYPE_SOUND_DOWN events
/// during a brief window after the Xiaomi remote reports a volume button press.
/// Normal Mac keyboard volume controls remain unaffected!
@Observable
final class VolumeKeyInterceptor {
    private(set) var isEnabled: Bool = false
    private(set) var isTrusted: Bool = false
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var suppressionDeadline: TimeInterval = 0

    init() {
        _ = checkAccessibility()
    }

    deinit {
        stop()
    }

    @discardableResult
    func checkAccessibility() -> Bool {
        isTrusted = AXIsProcessTrusted()
        return isTrusted
    }

    func requestAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }

    /// Activate suppression window. Any system volume key arriving within `duration` will be dropped.
    func suppressNext(duration: TimeInterval = 0.35) {
        suppressionDeadline = Date().timeIntervalSince1970 + duration
        print("[VOLUME INTERCEPTOR] suppression active for \(duration)s")
    }

    var isSuppressed: Bool {
        return Date().timeIntervalSince1970 < suppressionDeadline
    }

    func start() {
        guard machPort == nil else { return }
        guard checkAccessibility() else {
            print("[VolumeInterceptor] Accessibility permission not granted; system volume will not be intercepted")
            return
        }

        let eventMask: CGEventMask = (1 << 14) // NSSystemDefined
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let interceptor = Unmanaged<VolumeKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = interceptor.machPort {
                        CGEvent.tapEnable(tap: port, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                if type.rawValue == 14 { // NSSystemDefined
                    if let nsEvent = NSEvent(cgEvent: event),
                       nsEvent.type == .systemDefined,
                       nsEvent.subtype.rawValue == 8 {
                        let data1 = nsEvent.data1
                        let keyCode = Int((data1 & 0xFFFF0000) >> 16)
                        if keyCode == Int(NX_KEYTYPE_SOUND_UP) || keyCode == Int(NX_KEYTYPE_SOUND_DOWN) {
                            let suppressed = interceptor.isSuppressed
                            print("[VOLUME TAP] keyCode=\(keyCode == Int(NX_KEYTYPE_SOUND_UP) ? "UP" : "DOWN") suppressed=\(suppressed)")
                            if suppressed {
                                // Drop the event: suppress macOS system volume change
                                return nil
                            }
                        }
                    }
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: context
        ) else {
            print("[VolumeInterceptor] Failed to create CGEventTap")
            return
        }

        self.machPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.isEnabled = true
        print("[VolumeInterceptor] Active: Xiaomi remote volume keys will be suppressed from changing system volume")
    }

    func stop() {
        if let tap = machPort {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                self.runLoopSource = nil
            }
            self.machPort = nil
        }
        self.isEnabled = false
    }
}
