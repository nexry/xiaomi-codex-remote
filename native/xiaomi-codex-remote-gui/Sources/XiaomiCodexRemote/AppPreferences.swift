import AppKit
import Foundation

enum AppPreferences {
    static let hideDockIconKey = "hideDockIcon"
    static let keyMappingKey = "xiaomiKeyMapping"

    static func hideDockIcon(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: hideDockIconKey)
    }

    static func activationPolicy(hideDockIcon: Bool) -> NSApplication.ActivationPolicy {
        hideDockIcon ? .accessory : .regular
    }

    static func keyMapping(in defaults: UserDefaults = .standard) -> [String: XiaomiBinding?] {
        guard let data = defaults.data(forKey: keyMappingKey),
              let stored = try? JSONDecoder().decode([String: XiaomiBinding?].self, from: data),
              let validated = try? XiaomiKeyMapping.make(overrides: stored) else {
            return XiaomiKeyMapping.defaults
        }
        return validated
    }

    static func saveKeyMapping(
        _ mapping: [String: XiaomiBinding?],
        in defaults: UserDefaults = .standard
    ) throws {
        let validated = try XiaomiKeyMapping.make(overrides: mapping)
        defaults.set(try JSONEncoder().encode(validated), forKey: keyMappingKey)
    }

    static func resetKeyMapping(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: keyMappingKey)
    }

    @discardableResult
    static func applyDockIconVisibility(
        hidden: Bool,
        activateWhenVisible: Bool = false,
        application: NSApplication = .shared
    ) -> Bool {
        let didApply = application.setActivationPolicy(activationPolicy(hideDockIcon: hidden))
        if !hidden && activateWhenVisible {
            application.activate(ignoringOtherApps: true)
        }
        return didApply
    }
}
