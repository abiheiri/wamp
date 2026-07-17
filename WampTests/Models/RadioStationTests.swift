import Testing
import Foundation
@testable import Wamp

@Suite("RadioStation")
struct RadioStationTests {

    private func rbStation(id: String = "9617a958-0601-11e8-ae97-52543be04c81",
                           name: String = "SomaFM Groove Salad",
                           popularity: Int = 4200) -> RadioStation {
        RadioStation(id: id, source: .radioBrowser, name: name, genre: "ambient",
                     bitrate: 128, popularity: popularity, format: "MP3",
                     streamURL: URL(string: "https://ice2.somafm.com/groovesalad-128-mp3"))
    }

    // MARK: - Mapping from ShoutcastStation

    @Test func initFromShoutcast_mapsAllFields() {
        let sc = ShoutcastStation(id: 1552431, name: "Rock Classics", genre: "Rock",
                                  bitrate: 64, listeners: 10, format: "MP3",
                                  streamURL: URL(string: "http://example.com/stream"))
        let station = RadioStation(from: sc)

        #expect(station.id == "sc:1552431")
        #expect(station.source == .shoutcast)
        #expect(station.name == "Rock Classics")
        #expect(station.genre == "Rock")
        #expect(station.bitrate == 64)
        #expect(station.popularity == 10)
        #expect(station.format == "MP3")
        #expect(station.streamURL?.absoluteString == "http://example.com/stream")
    }

    @Test func shoutcastID_recoversNumericID() {
        let sc = ShoutcastStation(id: 99498012, name: "ROCK ANTENNE", genre: "Rock",
                                  bitrate: 192, listeners: 500, format: "MP3", streamURL: nil)
        #expect(RadioStation(from: sc).shoutcastID == 99498012)
    }

    @Test func shoutcastID_nilForRadioBrowserStations() {
        #expect(rbStation().shoutcastID == nil)
    }

    // MARK: - Equatable / Identifiable

    @Test func equatable_sameIDAreEqual() {
        let a = rbStation(name: "Name A", popularity: 1)
        let b = rbStation(name: "Name B", popularity: 999)
        #expect(a == b)
    }

    @Test func equatable_differentIDAreNotEqual() {
        #expect(rbStation(id: "uuid-1") != rbStation(id: "uuid-2"))
    }

    @Test func equatable_sourcesNeverCollide() {
        // A SHOUTcast numeric id can't equal a Radio Browser uuid thanks to the "sc:" prefix.
        let sc = RadioStation(from: ShoutcastStation(id: 1, name: "A", genre: "", bitrate: 0,
                                                     listeners: 0, format: "", streamURL: nil))
        #expect(sc != rbStation(id: "1"))
    }

    // MARK: - Codable

    @Test func codableRoundTrip_preservesAllFields() throws {
        let original = rbStation()
        let decoded = try JSONDecoder().decode(RadioStation.self, from: JSONEncoder().encode(original))

        #expect(decoded.id == original.id)
        #expect(decoded.source == original.source)
        #expect(decoded.name == original.name)
        #expect(decoded.genre == original.genre)
        #expect(decoded.bitrate == original.bitrate)
        #expect(decoded.popularity == original.popularity)
        #expect(decoded.format == original.format)
        #expect(decoded.streamURL == original.streamURL)
    }

    // MARK: - Display

    @Test func displayString_formatWithBitrate() {
        #expect(rbStation().displayString == "SomaFM Groove Salad (128 kbps MP3)")
    }

    @Test func popularityDisplay_abbreviates() {
        #expect(rbStation(popularity: 999).popularityDisplay == "999")
        #expect(rbStation(popularity: 5809).popularityDisplay == "5.8K")
        #expect(rbStation(popularity: 12000).popularityDisplay == "12K")
        #expect(rbStation(popularity: 1_500_000).popularityDisplay == "1.5M")
    }

    // MARK: - Favorites decoding (new format + legacy migration)

    @Test func decodeFavorites_newFormat() throws {
        let data = try JSONEncoder().encode([rbStation()])
        let favorites = RadioStation.decodeFavorites(data)
        #expect(favorites?.count == 1)
        #expect(favorites?.first?.source == .radioBrowser)
        #expect(favorites?.first?.name == "SomaFM Groove Salad")
    }

    @Test func decodeFavorites_legacyShoutcastFormat_migrates() {
        let legacy = """
        [
            {
                "ID": 1552431,
                "Name": "Rock Classics",
                "Genre": "Rock",
                "Bitrate": 64,
                "Listeners": 10,
                "Format": "MP3",
                "StreamUrl": "http://example.com/stream"
            },
            {
                "ID": 99498012,
                "Name": "ROCK ANTENNE",
                "Genre": "Rock",
                "Bitrate": 192,
                "Listeners": 500,
                "Format": "MP3",
                "StreamUrl": null
            }
        ]
        """
        let favorites = RadioStation.decodeFavorites(Data(legacy.utf8))
        #expect(favorites?.count == 2)
        #expect(favorites?[0].id == "sc:1552431")
        #expect(favorites?[0].source == .shoutcast)
        #expect(favorites?[0].streamURL?.absoluteString == "http://example.com/stream")
        #expect(favorites?[1].id == "sc:99498012")
        #expect(favorites?[1].popularity == 500)
    }

    @Test func decodeFavorites_garbageReturnsNil() {
        #expect(RadioStation.decodeFavorites(Data("not json".utf8)) == nil)
    }

    @Test func decodeFavorites_emptyArray() {
        #expect(RadioStation.decodeFavorites(Data("[]".utf8))?.isEmpty == true)
    }
}
