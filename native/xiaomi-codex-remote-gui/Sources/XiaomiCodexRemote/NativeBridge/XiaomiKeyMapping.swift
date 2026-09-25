import Foundation

enum XiaomiBindingKind: String, Codable {
    case key
    case rotate
    case joystick
}

struct XiaomiBinding: Codable, Equatable {
    let kind: XiaomiBindingKind
    let keycode: String?
    let agent: Int?
    let angle: Double?
}

enum XiaomiKeyMappingError: LocalizedError, Equatable {
    case invalidLogicalKey(String)
    case invalidKeycode(String)

    var errorDescription: String? {
        switch self {
        case let .invalidLogicalKey(key):
            return "Invalid Xiaomi logical key: \(key)"
        case let .invalidKeycode(keycode):
            return "Invalid Codex keycode: \(keycode)"
        }
    }
}

struct XiaomiKeyMapping {
    static let defaults: [String: XiaomiBinding?] = [
        "home": .some(.init(kind: .key, keycode: "AG00", agent: 0, angle: nil)),
        "menu": .some(.init(kind: .key, keycode: "AG01", agent: 1, angle: nil)),
        "back": .some(.init(kind: .key, keycode: "ACT08", agent: nil, angle: nil)),
        "ok": .some(.init(kind: .key, keycode: "ENC_CLK", agent: nil, angle: nil)),
        "voice": .some(.init(kind: .key, keycode: "ACT10", agent: nil, angle: nil)),
        "volume_up": .some(.init(kind: .rotate, keycode: "ENC_CC", agent: nil, angle: nil)),
        "volume_down": .some(.init(kind: .rotate, keycode: "ENC_CW", agent: nil, angle: nil)),
        "up": .some(.init(kind: .joystick, keycode: nil, agent: nil, angle: 0.75)),
        "down": .some(.init(kind: .joystick, keycode: nil, agent: nil, angle: 0.25)),
        "left": .some(.init(kind: .joystick, keycode: nil, agent: nil, angle: 0.5)),
        "right": .some(.init(kind: .joystick, keycode: nil, agent: nil, angle: 0.0)),
        "power": nil,
    ]

    static func make(overrides: [String: XiaomiBinding?]) throws -> [String: XiaomiBinding?] {
        var validated: [(String, XiaomiBinding?)] = []
        for (logicalKey, binding) in overrides {
            guard logicalKey.range(of: #"^[a-z][a-z0-9_]*$"#, options: .regularExpression) != nil else {
                throw XiaomiKeyMappingError.invalidLogicalKey(logicalKey)
            }
            validated.append((logicalKey, try binding.map(validate)))
        }

        var result = defaults
        for (logicalKey, binding) in validated {
            result.updateValue(binding, forKey: logicalKey)
        }
        return result
    }

    private static func validate(_ binding: XiaomiBinding) throws -> XiaomiBinding {
        switch binding.kind {
        case .key, .rotate:
            guard let keycode = binding.keycode, CodexProtocol.Key.agents.contains(keycode) || CodexProtocol.Key.actions.contains(keycode) || keycode == CodexProtocol.Key.encoderCCW || keycode == CodexProtocol.Key.encoderCW || keycode == CodexProtocol.Key.encoderClick else {
                throw XiaomiKeyMappingError.invalidKeycode(binding.keycode ?? "nil")
            }
            let isAgent = CodexProtocol.Key.agents.contains(keycode)
            return XiaomiBinding(
                kind: binding.kind,
                keycode: keycode,
                agent: isAgent ? CodexProtocol.Key.agents.firstIndex(of: keycode) : nil,
                angle: nil
            )
        case .joystick:
            return XiaomiBinding(
                kind: .joystick,
                keycode: nil,
                agent: nil,
                angle: binding.angle ?? 0.0
            )
        }
    }
}
