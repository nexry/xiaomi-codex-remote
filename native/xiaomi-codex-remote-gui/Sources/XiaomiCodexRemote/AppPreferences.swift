import AppKit
import Foundation

enum AppPreferences {
    static let hideDockIconKey = "hideDockIcon"

    static func hideDockIcon(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: hideDockIconKey)
    }

    static func activationPolicy(hideDockIcon: Bool) -> NSApplication.ActivationPolicy {
        hideDockIcon ? .accessory : .regular
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
