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

    func testKeyMappingPersistsDisabledAndCustomBindings() throws {
        let suiteName = "AppPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var mapping = XiaomiKeyMapping.defaults
        mapping.updateValue(nil, forKey: "back")
        mapping.updateValue(
            .init(kind: .key, keycode: "AG05", agent: 5, angle: nil),
            forKey: "menu"
        )

        try AppPreferences.saveKeyMapping(mapping, in: defaults)
        let restored = AppPreferences.keyMapping(in: defaults)

        XCTAssertTrue(restored.keys.contains("back"))
        XCTAssertNil(restored["back"]!)
        XCTAssertEqual(restored["menu"]!, .init(kind: .key, keycode: "AG05", agent: 5, angle: nil))
    }

    func testInvalidStoredKeyMappingFallsBackToDefaults() {
        let suiteName = "AppPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: AppPreferences.keyMappingKey)

        XCTAssertEqual(AppPreferences.keyMapping(in: defaults), XiaomiKeyMapping.defaults)
    }
}
