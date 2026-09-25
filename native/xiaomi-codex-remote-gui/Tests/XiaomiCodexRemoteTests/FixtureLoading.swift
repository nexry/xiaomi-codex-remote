import Foundation
import XCTest

struct FrameFixture: Decodable {
    let name: String
    let message: String
    let channel: UInt8
    let frames: [String]

    static func load() throws -> [FrameFixture] {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "codex-frames",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        return try JSONDecoder().decode([FrameFixture].self, from: Data(contentsOf: url))
    }
}

extension Data {
    init(hex: String) {
        precondition(hex.count.isMultiple(of: 2))
        self.init(stride(from: 0, to: hex.count, by: 2).map { offset in
            UInt8(hex[
                hex.index(hex.startIndex, offsetBy: offset)..<hex.index(hex.startIndex, offsetBy: offset + 2)
            ], radix: 16)!
        })
    }
}
