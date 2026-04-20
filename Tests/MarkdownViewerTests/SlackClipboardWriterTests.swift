import XCTest
@testable import MarkdownViewerCore

final class SlackClipboardWriterTests: XCTestCase {
    func testEncodesChromiumWebCustomDataEntries() throws {
        let data = ChromiumWebCustomDataEncoder.encode(
            entries: [
                ChromiumWebCustomDataEntry(
                    type: "public.utf8-plain-text",
                    value: "Hello"
                ),
                ChromiumWebCustomDataEntry(
                    type: "slack/texty",
                    value: #"{"ops":[{"insert":"Hello"}]}"#
                )
            ]
        )

        let decoded = try decodeChromiumEntries(from: data)

        XCTAssertEqual(decoded["public.utf8-plain-text"], "Hello")
        XCTAssertEqual(decoded["slack/texty"], #"{"ops":[{"insert":"Hello"}]}"#)
    }

    private func decodeChromiumEntries(from data: Data) throws -> [String: String] {
        let payloadSize = try readUInt32(from: data, offset: 0)
        XCTAssertEqual(Int(payloadSize), data.count - 4)

        let entryCount = try readUInt32(from: data, offset: 4)
        var offset = 8
        var output: [String: String] = [:]

        for _ in 0..<entryCount {
            let type = try readString16(from: data, offset: &offset)
            let value = try readString16(from: data, offset: &offset)
            output[type] = value
        }

        return output
    }

    private func readUInt32(from data: Data, offset: Int) throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw NSError(domain: "SlackClipboardWriterTests", code: 1)
        }

        return data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { rawBuffer in
            UInt32(littleEndian: rawBuffer.load(as: UInt32.self))
        }
    }

    private func readString16(from data: Data, offset: inout Int) throws -> String {
        let count = Int(try readUInt32(from: data, offset: offset))
        offset += 4
        let byteCount = count * 2
        guard offset + byteCount <= data.count else {
            throw NSError(domain: "SlackClipboardWriterTests", code: 2)
        }

        let stringData = data.subdata(in: offset..<(offset + byteCount))
        guard let string = String(data: stringData, encoding: .utf16LittleEndian) else {
            throw NSError(domain: "SlackClipboardWriterTests", code: 3)
        }

        offset += byteCount
        let padding = (4 - (offset % 4)) % 4
        offset += padding
        return string
    }
}
