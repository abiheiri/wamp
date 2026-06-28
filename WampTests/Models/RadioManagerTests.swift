import Testing
import Foundation
@testable import Wamp

@Suite("RadioManager")
struct RadioManagerTests {

    private func station(_ id: Int, _ name: String, genre: String = "Rock") -> ShoutcastStation {
        ShoutcastStation(id: id, name: name, genre: genre, bitrate: 128,
                         listeners: 0, format: "MP3", streamURL: nil)
    }

    // MARK: - Filtering

    @Test func filter_byName_caseInsensitive() {
        let list = [station(1, "Jazz FM"), station(2, "Rock Hard"), station(3, "Smooth Jazz")]
        #expect(RadioManager.filter(list, query: "jazz").map(\.id) == [1, 3])
    }

    @Test func filter_byGenre() {
        let list = [station(1, "A", genre: "Metal"), station(2, "B", genre: "Jazz")]
        #expect(RadioManager.filter(list, query: "metal").map(\.id) == [1])
    }

    @Test func filter_emptyOrWhitespaceQuery_returnsAll() {
        let list = [station(1, "A"), station(2, "B")]
        #expect(RadioManager.filter(list, query: "").count == 2)
        #expect(RadioManager.filter(list, query: "   ").count == 2)
    }

    @Test func filter_noMatch_returnsEmpty() {
        let list = [station(1, "A"), station(2, "B")]
        #expect(RadioManager.filter(list, query: "zzz").isEmpty)
    }

    // MARK: - Adjacent station navigation

    @Test func adjacent_next_advancesAndWraps() {
        let list = [station(1, "A"), station(2, "B"), station(3, "C")]
        #expect(RadioManager.adjacentStation(to: 1, in: list, offset: 1)?.id == 2)
        #expect(RadioManager.adjacentStation(to: 3, in: list, offset: 1)?.id == 1)
    }

    @Test func adjacent_previous_retreatsAndWraps() {
        let list = [station(1, "A"), station(2, "B"), station(3, "C")]
        #expect(RadioManager.adjacentStation(to: 2, in: list, offset: -1)?.id == 1)
        #expect(RadioManager.adjacentStation(to: 1, in: list, offset: -1)?.id == 3)
    }

    @Test func adjacent_unknownOrNilCurrent_returnsFirst() {
        let list = [station(1, "A"), station(2, "B")]
        #expect(RadioManager.adjacentStation(to: nil, in: list, offset: 1)?.id == 1)
        #expect(RadioManager.adjacentStation(to: 99, in: list, offset: -1)?.id == 1)
    }

    @Test func adjacent_emptyList_returnsNil() {
        #expect(RadioManager.adjacentStation(to: nil, in: [], offset: 1) == nil)
    }

    // MARK: - Favorites toggle

    @Test func toggleFavorites_addsWhenAbsent() {
        let result = RadioManager.toggledFavorites([station(1, "A")], toggling: station(2, "B"))
        #expect(result.map(\.id) == [1, 2])
    }

    @Test func toggleFavorites_removesWhenPresent() {
        let list = [station(1, "A"), station(2, "B"), station(3, "C")]
        #expect(RadioManager.toggledFavorites(list, toggling: station(2, "B")).map(\.id) == [1, 3])
    }

    @Test func toggleFavorites_matchesById_notIdentity() {
        // Same id, different name/bitrate still toggles off.
        let list = [station(7, "Original Name")]
        let result = RadioManager.toggledFavorites(list, toggling: station(7, "Different Name"))
        #expect(result.isEmpty)
    }

    @Test func toggleFavorites_emptyList_adds() {
        #expect(RadioManager.toggledFavorites([], toggling: station(1, "A")).map(\.id) == [1])
    }
}
