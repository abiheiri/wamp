import Testing
import Foundation
@testable import Wamp

@Suite("ICYMetadataParser")
struct ICYMetadataParserTests {

    // MARK: - Parse metadata block

    @Test func parseBlock_extractsStreamTitle() {
        let raw = "StreamTitle='Bohemian Rhapsody - Queen';StreamUrl='';"
        let data = raw.data(using: .utf8)!
        let parsed = ICYMetadataParser.parse(data)

        #expect(parsed?.streamTitle == "Bohemian Rhapsody - Queen")
        #expect(parsed?.streamUrl == "")
    }

    @Test func parseBlock_extractsBothFields() {
        let raw = "StreamTitle='Song Name';StreamUrl='http://example.com';"
        let data = raw.data(using: .utf8)!
        let parsed = ICYMetadataParser.parse(data)

        #expect(parsed?.streamTitle == "Song Name")
        #expect(parsed?.streamUrl == "http://example.com")
    }

    @Test func parseBlock_emptyTitle() {
        let raw = "StreamTitle='';StreamUrl='';"
        let data = raw.data(using: .utf8)!
        let parsed = ICYMetadataParser.parse(data)

        #expect(parsed?.streamTitle == "")
        #expect(parsed?.streamUrl == "")
    }

    @Test func parseBlock_nullPaddedData() {
        // Real metadata blocks are null-padded
        let raw = "StreamTitle='Track Name';"
        let padded = raw + String(repeating: "\0", count: 8)
        let data = padded.data(using: .utf8)!
        let parsed = ICYMetadataParser.parse(data)

        #expect(parsed?.streamTitle == "Track Name")
    }

    @Test func parseBlock_onlyStreamTitle() {
        let raw = "StreamTitle='Just Title';"
        let data = raw.data(using: .utf8)!
        let parsed = ICYMetadataParser.parse(data)

        #expect(parsed?.streamTitle == "Just Title")
        #expect(parsed?.streamUrl == nil)
    }

    @Test func parseBlock_malformed_noQuotes() {
        let raw = "garbage data here"
        let data = raw.data(using: .utf8)!
        let parsed = ICYMetadataParser.parse(data)

        #expect(parsed == nil)
    }

    @Test func parseBlock_emptyData() {
        let data = Data()
        let parsed = ICYMetadataParser.parse(data)

        #expect(parsed == nil)
    }

    @Test func parseBlock_singleQuoteInTitle() {
        // Titles like "Don't Stop" have a literal apostrophe
        let raw = "StreamTitle='Don\\'t Stop Believin\\'';"
        let data = raw.data(using: .utf8)!
        let parsed = ICYMetadataParser.parse(data)

        #expect(parsed?.streamTitle == "Don't Stop Believin'")
    }

    // MARK: - Extract metadata interval from HTTP headers

    @Test func metadataInterval_fromHeaders() {
        let headers = ["icy-metaint": "8192"]
        let interval = ICYMetadataParser.metadataInterval(from: headers)
        #expect(interval == 8192)
    }

    @Test func metadataInterval_missingHeader() {
        let headers: [String: String] = [:]
        let interval = ICYMetadataParser.metadataInterval(from: headers)
        #expect(interval == 0)
    }

    @Test func metadataInterval_invalidValue() {
        let headers = ["icy-metaint": "not-a-number"]
        let interval = ICYMetadataParser.metadataInterval(from: headers)
        #expect(interval == 0)
    }

    @Test func metadataInterval_zero() {
        let headers = ["icy-metaint": "0"]
        let interval = ICYMetadataParser.metadataInterval(from: headers)
        #expect(interval == 0)
    }
}
