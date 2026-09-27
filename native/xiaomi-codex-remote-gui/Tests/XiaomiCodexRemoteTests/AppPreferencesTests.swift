import AppKit
import XCTest
@testable import XiaomiCodexRemote

final class AppPreferencesTests: XCTestCase {
    func testDockIconIsVisibleByDefaultAndPreferencePersists() {
        let suiteName = "AppPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(AppPreferences.hideDockIcon(in: defaults))

        defaults.set(true, forKey: AppPreferences.hideDockIconKey)
        XCTAssertTrue(AppPreferences.hideDockIcon(in: defaults))
    }

    func testDockVisibilityMapsToApplicationActivationPolicy() {
        XCTAssertEqual(AppPreferences.activationPolicy(hideDockIcon: false), .regular)
        XCTAssertEqual(AppPreferences.activationPolicy(hideDockIcon: true), .accessory)
    }
}
