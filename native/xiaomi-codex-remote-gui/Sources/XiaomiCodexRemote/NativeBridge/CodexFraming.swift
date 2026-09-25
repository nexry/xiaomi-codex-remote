import Foundation

struct CodexMessage: Equatable {
    let channel: UInt8
    let message: String
}

enum CodexFrameEncoder {
    static func encode(_ message: String, channel: UInt8 = CodexChannel.rpc.rawValue) -> [Data] {
        let bytes = Array(message.utf8)
        var frames: [Data] = []
        var offset = 0

        repeat {
            let count = min(CodexProtocol.maxPayload, bytes.count - offset)
            var frame = [UInt8](repeating: 0, count: CodexProtocol.reportSize)
            frame[0] = CodexProtocol.reportID
            frame[1] = channel
            frame[2] = UInt8(count)
            if count > 0 {
                frame.replaceSubrange(3..<(3 + count), with: bytes[offset..<(offset + count)])
            }
            frames.append(Data(frame))
            offset += count
        } while offset < bytes.count

        return frames
    }
}

struct CodexFrameReassembler {
    private var buffers: [UInt8: Data] = [:]

    mutating func push<D: DataProtocol>(_ report: D) -> [CodexMessage] {
        let bytes = Array(report)
        let base = bytes.first == CodexProtocol.reportID ? 1 : 0
        guard bytes.count >= base + 2 else { return [] }

        let channel = bytes[base]
        let length = min(Int(bytes[base + 1]), bytes.count - base - 2)
        buffers[channel, default: Data()].append(contentsOf: bytes[(base + 2)..<(base + 2 + length)])
        // Keep raw bytes until a split UTF-8 scalar is complete.
        guard buffers[channel]!.count <= 1024 * 1024 else {
            buffers[channel] = Data()
            return []
        }

        if channel == CodexChannel.rpc.rawValue {
            return extractRPC(channel: channel)
        }
        return extractLines(channel: channel)
    }

    private mutating func extractLines(channel: UInt8) -> [CodexMessage] {
        guard let text = String(data: buffers[channel, default: Data()], encoding: .utf8) else { return [] }
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        buffers[channel] = Data(String(parts.last ?? "").utf8)
        return parts.dropLast().compactMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : CodexMessage(channel: channel, message: value)
        }
    }

    private mutating func extractRPC(channel: UInt8) -> [CodexMessage] {
        guard let text = String(data: buffers[channel, default: Data()], encoding: .utf8) else { return [] }
        let (objects, remainder) = JSONObjects.extract(from: text)
        buffers[channel] = Data(remainder.utf8)
        return objects.map { CodexMessage(channel: channel, message: $0) }
    }
}

private enum JSONObjects {
    static func extract(from buffer: String) -> (objects: [String], remainder: String) {
        let characters = Array(buffer)
        var objects: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var start: Int?
        var lastEnd = 0

        for index in characters.indices {
            let character = characters[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
            } else if character == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let objectStart = start {
                    objects.append(String(characters[objectStart...index]))
                    lastEnd = index + 1
                    start = nil
                }
            }
        }

        let remainder: String
        if depth > 0, let objectStart = start {
            remainder = String(characters[objectStart...])
        } else if lastEnd < characters.count {
            remainder = String(characters[lastEnd...])
        } else {
            remainder = ""
        }

        return (objects, remainder)
    }
}
