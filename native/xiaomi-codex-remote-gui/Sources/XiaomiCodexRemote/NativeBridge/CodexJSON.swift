import Foundation
import CoreFoundation

indirect enum CodexJSON: Equatable {
    case object([String: CodexJSON])
    case array([CodexJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    static func parse(_ string: String) throws -> CodexJSON {
        let value = try JSONSerialization.jsonObject(with: Data(string.utf8))
        return try fromFoundation(value)
    }

    func encodedLine() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: foundationValue, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return string + "\n"
    }

    subscript(_ key: String) -> CodexJSON? {
        guard case let .object(object) = self else { return nil }
        return object[key]
    }

    var intValue: Int? {
        switch self {
        case let .number(value):
            guard value.isFinite, value.rounded() == value else { return nil }
            return Int(exactly: value)
        case let .string(value):
            return Int(value)
        default:
            return nil
        }
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    private static func fromFoundation(_ value: Any) throws -> CodexJSON {
        switch value {
        case is NSNull:
            return .null
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
            return .number(value.doubleValue)
        case let value as String:
            return .string(value)
        case let value as [Any]:
            return .array(try value.map(fromFoundation))
        case let value as [String: Any]:
            return .object(try value.mapValues(fromFoundation))
        default:
            throw CocoaError(.propertyListReadCorrupt)
        }
    }

    private var foundationValue: Any {
        switch self {
        case let .object(value):
            return value.mapValues(\.foundationValue)
        case let .array(value):
            return value.map(\.foundationValue)
        case let .string(value):
            return value
        case let .number(value):
            return value
        case let .bool(value):
            return value
        case .null:
            return NSNull()
        }
    }
}
