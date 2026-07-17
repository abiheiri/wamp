import Testing
import Foundation
@testable import Wamp

@Suite("RadioStationMerger")
struct RadioStationMergerTests {

    private func sc(_ id: Int, _ name: String, listeners: Int = 0) -> RadioStation {
        RadioStation(from: ShoutcastStation(id: id, name: name, genre: "Rock", bitrate: 128,
                                            listeners: listeners, format: "MP3", streamURL: nil))
    }

    private func rb(_ id: String, _ name: String, clicks: Int = 0) -> RadioStation {
        RadioStation(id: id, source: .radioBrowser, name: name, genre: "rock", bitrate: 128,
                     popularity: clicks, format: "MP3",
                     streamURL: URL(string: "http://x.example/\(id)"))
    }

    // MARK: - Name normalization

    @Test func normalizedName_caseAndPunctuationInsensitive() {
        #expect(RadioStationMerger.normalizedName("ROCK ANTENNE") ==
                RadioStationMerger.normalizedName("Rock-Antenne!"))
    }

    @Test func normalizedName_stripsBitrateAndFormatTokens() {
        #expect(RadioStationMerger.normalizedName("Rock Antenne 128k") ==
                RadioStationMerger.normalizedName("Rock Antenne"))
        #expect(RadioStationMerger.normalizedName("Rock Antenne 128kbps") ==
                RadioStationMerger.normalizedName("Rock Antenne"))
        #expect(RadioStationMerger.normalizedName("Rock Antenne MP3") ==
                RadioStationMerger.normalizedName("Rock Antenne AAC"))
    }

    @Test func normalizedName_keepsMeaningfulNumbers() {
        #expect(RadioStationMerger.normalizedName("BBC Radio 1") !=
                RadioStationMerger.normalizedName("BBC Radio 2"))
    }

    // MARK: - Interleaving

    @Test func merged_interleavesByRank() {
        let result = RadioStationMerger.merged([sc(1, "SC One"), sc(2, "SC Two")],
                                               [rb("u1", "RB One"), rb("u2", "RB Two")])
        #expect(result.map(\.name) == ["SC One", "RB One", "SC Two", "RB Two"])
    }

    @Test func merged_appendsRemainderWhenListsUneven() {
        let result = RadioStationMerger.merged([sc(1, "SC One")],
                                               [rb("u1", "RB One"), rb("u2", "RB Two"), rb("u3", "RB Three")])
        #expect(result.map(\.name) == ["SC One", "RB One", "RB Two", "RB Three"])
    }

    @Test func merged_oneEmptyList_returnsOther() {
        let rbOnly = [rb("u1", "A"), rb("u2", "B")]
        #expect(RadioStationMerger.merged([], rbOnly).map(\.id) == ["u1", "u2"])
        let scOnly = [sc(1, "A"), sc(2, "B")]
        #expect(RadioStationMerger.merged(scOnly, []).map(\.id) == ["sc:1", "sc:2"])
    }

    @Test func merged_bothEmpty() {
        #expect(RadioStationMerger.merged([], []).isEmpty)
    }

    // MARK: - Deduplication

    @Test func merged_dropsCrossSourceDuplicates_keepingEarlierRank() {
        // "Rock Antenne" appears in both directories; the SC copy is rank 0 and
        // interleaves first, so the RB copy (rank 1) is dropped.
        let result = RadioStationMerger.merged(
            [sc(1, "ROCK ANTENNE", listeners: 500), sc(2, "SC Two")],
            [rb("u1", "RB One"), rb("u2", "Rock-Antenne 128k", clicks: 9000)])
        #expect(result.map(\.name) == ["ROCK ANTENNE", "RB One", "SC Two"])
    }

    @Test func merged_duplicateAtSameRank_firstListWins() {
        let result = RadioStationMerger.merged([sc(1, "Same Station")],
                                               [rb("u1", "Same Station")])
        #expect(result.count == 1)
        #expect(result[0].source == .shoutcast)
    }

    @Test func merged_dedupsWithinASingleList() {
        let result = RadioStationMerger.merged([], [rb("u1", "Dup FM"), rb("u2", "Dup FM!")])
        #expect(result.map(\.id) == ["u1"])
    }

    @Test func merged_distinctStationsAllSurvive() {
        let result = RadioStationMerger.merged([sc(1, "Alpha"), sc(2, "Beta")],
                                               [rb("u1", "Gamma"), rb("u2", "Delta")])
        #expect(result.count == 4)
    }
}
