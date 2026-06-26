import Testing
import Foundation
@testable import Wamp

@MainActor
@Suite("ShoutcastStation")
struct ShoutcastStationTests {

    // MARK: - Initialization

    @Test func initWithAllFields() {
        let station = ShoutcastStation(
            id: 12345,
            name: "Test FM",
            genre: "Rock",
            bitrate: 128,
            listeners: 42,
            format: "MP3",
            streamURL: URL(string: "http://example.com:8000/stream")
        )
        #expect(station.id == 12345)
        #expect(station.name == "Test FM")
        #expect(station.genre == "Rock")
        #expect(station.bitrate == 128)
        #expect(station.listeners == 42)
        #expect(station.format == "MP3")
        #expect(station.streamURL?.absoluteString == "http://example.com:8000/stream")
    }

    @Test func initWithStreamURLOptionalNil() {
        let station = ShoutcastStation(
            id: 1,
            name: "No URL Station",
            genre: "Jazz",
            bitrate: 64,
            listeners: 0,
            format: "AAC",
            streamURL: nil
        )
        #expect(station.streamURL == nil)
        #expect(station.id == 1)
        #expect(station.name == "No URL Station")
    }

    // MARK: - Codable

    @Test func codableRoundTrip_preservesAllFields() throws {
        let original = ShoutcastStation(
            id: 99999,
            name: "Encodable FM",
            genre: "Electronic",
            bitrate: 320,
            listeners: 1500,
            format: "MP3",
            streamURL: URL(string: "https://secure.stream.example:8443/stream")
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ShoutcastStation.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.genre == original.genre)
        #expect(decoded.bitrate == original.bitrate)
        #expect(decoded.listeners == original.listeners)
        #expect(decoded.format == original.format)
        #expect(decoded.streamURL == original.streamURL)
    }

    @Test func codableRoundTrip_nilStreamURL() throws {
        let original = ShoutcastStation(
            id: 42,
            name: "Nil URL",
            genre: "Ambient",
            bitrate: 96,
            listeners: 0,
            format: "AAC",
            streamURL: nil
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ShoutcastStation.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.streamURL == nil)
    }

    // MARK: - Identifiable

    @Test func identifiableConformance_usesStationID() {
        let a = ShoutcastStation(
            id: 1, name: "A", genre: "", bitrate: 0, listeners: 0, format: "", streamURL: nil
        )
        let b = ShoutcastStation(
            id: 2, name: "B", genre: "", bitrate: 0, listeners: 0, format: "", streamURL: nil
        )
        #expect(a.id != b.id)
        #expect(a.id == 1)
        #expect(b.id == 2)
    }

    // MARK: - Equatable

    @Test func equatable_sameIDAreEqual() {
        let station1 = ShoutcastStation(
            id: 100, name: "Same", genre: "Pop", bitrate: 128, listeners: 10, format: "MP3",
            streamURL: URL(string: "http://a.com/stream")
        )
        let station2 = ShoutcastStation(
            id: 100, name: "Different Name", genre: "Rock", bitrate: 256, listeners: 999, format: "AAC",
            streamURL: URL(string: "http://b.com/stream")
        )
        #expect(station1 == station2) // same ID → equal
    }

    @Test func equatable_differentIDAreNotEqual() {
        let station1 = ShoutcastStation(
            id: 1, name: "X", genre: "", bitrate: 0, listeners: 0, format: "", streamURL: nil
        )
        let station2 = ShoutcastStation(
            id: 2, name: "X", genre: "", bitrate: 0, listeners: 0, format: "", streamURL: nil
        )
        #expect(station1 != station2)
    }

    // MARK: - Display string

    @Test func displayString_formatWithBitrate() {
        let station = ShoutcastStation(
            id: 1, name: "Cool Radio", genre: "Jazz", bitrate: 192, listeners: 0, format: "MP3",
            streamURL: nil
        )
        #expect(station.displayString == "Cool Radio (192 kbps MP3)")
    }

    @Test func displayString_formatAAC() {
        let station = ShoutcastStation(
            id: 1, name: "Chill FM", genre: "Ambient", bitrate: 128, listeners: 0, format: "AAC",
            streamURL: nil
        )
        #expect(station.displayString == "Chill FM (128 kbps AAC)")
    }

    @Test func displayString_zeroBitrate() {
        let station = ShoutcastStation(
            id: 1, name: "Unknown Rate", genre: "Talk", bitrate: 0, listeners: 0, format: "MP3",
            streamURL: nil
        )
        #expect(station.displayString == "Unknown Rate (0 kbps MP3)")
    }

    // MARK: - Decoding from directory JSON

    @Test func decodeFromDirectoryJSON() throws {
        let json = """
        {
            "ID": 99514043,
            "Name": "Test Radio",
            "Genre": "Electronic",
            "Bitrate": 128,
            "Listeners": 42,
            "Format": "MP3",
            "StreamUrl": "http://example.com:8000/stream"
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let station = try decoder.decode(ShoutcastStation.self, from: data)

        #expect(station.id == 99514043)
        #expect(station.name == "Test Radio")
        #expect(station.genre == "Electronic")
        #expect(station.bitrate == 128)
        #expect(station.listeners == 42)
        #expect(station.format == "MP3")
        #expect(station.streamURL?.absoluteString == "http://example.com:8000/stream")
    }

    @Test func decodeFromDirectoryJSON_missingStreamURL() throws {
        let json = """
        {
            "ID": 1,
            "Name": "No Stream",
            "Genre": "Rock",
            "Bitrate": 64,
            "Listeners": 0,
            "Format": "AAC"
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let station = try decoder.decode(ShoutcastStation.self, from: data)

        #expect(station.id == 1)
        #expect(station.streamURL == nil)
    }

    @Test func decodeFromDirectoryJSON_nullStreamURL() throws {
        let json = """
        {
            "ID": 99514043,
            "Name": "Test Radio",
            "Genre": "Electronic",
            "Bitrate": 128,
            "Listeners": 42,
            "Format": "MP3",
            "StreamUrl": null
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let station = try decoder.decode(ShoutcastStation.self, from: data)

        #expect(station.id == 99514043)
        #expect(station.name == "Test Radio")
        #expect(station.streamURL == nil)
    }

    @Test func decodeFromDirectoryJSON_extraFieldsIgnored() throws {
        let json = """
        {
            "ID": 99514043,
            "Name": "Test Radio",
            "Genre": "Electronic",
            "Bitrate": 128,
            "Listeners": 42,
            "Format": "MP3",
            "StreamUrl": null,
            "CurrentTrack": "Some Song",
            "IsPlaying": false
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let station = try decoder.decode(ShoutcastStation.self, from: data)

        #expect(station.id == 99514043)
        #expect(station.name == "Test Radio")
    }
}
