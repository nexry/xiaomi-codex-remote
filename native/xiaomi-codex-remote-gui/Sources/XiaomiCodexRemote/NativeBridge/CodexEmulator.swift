import Foundation

struct CodexLightingState: Equatable {
    var keys: CodexJSON?
    var ambient: CodexJSON?
    var slots: [CodexJSON?] = Array(repeating: nil, count: 6)
}

final class CodexEmulator {
    let firmwareVersion: String
    let battery: Int
    let charging: Bool
    let profileIndex: Int
    let layerIndex: Int

    var onSend: ((CodexJSON) -> Void)?
    var onLighting: ((CodexLightingState) -> Void)?

    private(set) var lighting = CodexLightingState()

    init(
        firmwareVersion: String = "1.0.0",
        battery: Int = 100,
        charging: Bool = false,
        profileIndex: Int = 0,
        layerIndex: Int = 0
    ) {
        self.firmwareVersion = firmwareVersion
        self.battery = battery
        self.charging = charging
        self.profileIndex = profileIndex
        self.layerIndex = layerIndex
    }

    func handle(_ message: CodexJSON) {
        guard let id = message["id"] ?? message["i"], let normalizedID = id.intValue else { return }
        let method = message["method"]?.stringValue ?? message["m"]?.stringValue
        let params = message["params"] ?? message["p"] ?? .null

        switch method {
        case CodexProtocol.Method.deviceStatus:
            send(response(normalizedID, statusObject))
        case CodexProtocol.Method.systemVersion:
            send(response(normalizedID, .string(firmwareVersion)))
        case CodexProtocol.Method.rgbConfig:
            applyRGB(params)
            send(response(normalizedID, .bool(true)))
        case CodexProtocol.Method.threadStatus:
            applyThreads(params)
            send(response(normalizedID, .bool(true)))
        case CodexProtocol.Method.lightsPreview:
            send(response(normalizedID, .bool(true)))
        default:
            send(response(normalizedID, .bool(true)))
        }
    }

    func sendKey(_ key: String, action: Int = CodexProtocol.Action.press, agent: Int? = nil) {
        var params: [String: CodexJSON] = [
            "k": .string(key),
            "act": .number(Double(action)),
        ]
        if let agent {
            params["ag"] = .number(Double(agent))
        }
        send(.object([
            "m": .string(CodexProtocol.Notify.hid),
            "p": .object(params),
        ]))
    }

    func sendJoystick(angle: Double, distance: Double) {
        send(.object([
            "m": .string(CodexProtocol.Notify.joystick),
            "p": .object([
                "a": .number(angle),
                "d": .number(distance)
            ])
        ]))
    }

    private var statusObject: CodexJSON {
        .object([
            "version": .string(firmwareVersion),
            "profile_index": .number(Double(profileIndex)),
            "layer_index": .number(Double(layerIndex)),
            "battery": .number(Double(battery)),
            "is_charging": .bool(charging),
        ])
    }

    private func response(_ id: Int, _ result: CodexJSON) -> CodexJSON {
        .object(["id": .number(Double(id)), "result": result])
    }

    private func send(_ value: CodexJSON) {
        onSend?(value)
    }

    private func applyRGB(_ params: CodexJSON) {
        guard case let .object(object) = params else { return }
        if let keys = object["keys"], keys != .null { lighting.keys = keys }
        if let ambient = object["ambient"], ambient != .null { lighting.ambient = ambient }
        onLighting?(lighting)
    }

    private func applyThreads(_ params: CodexJSON) {
        guard case let .array(threads) = params else { return }
        for thread in threads {
            guard let id = thread["id"]?.intValue, lighting.slots.indices.contains(id) else { continue }
            lighting.slots[id] = thread
        }
        onLighting?(lighting)
    }
}
