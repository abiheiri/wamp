import Testing
import Foundation
@testable import Wamp

@Suite("RadioGenre union")
struct RadioGenreTests {

    private func scGenre(_ name: String, id: Int = 1, subs: [String] = []) -> ShoutcastGenre {
        ShoutcastGenre(id: id, name: name, parentId: 0,
                       subgenres: subs.enumerated().map {
                           ShoutcastGenre(id: id * 100 + $0.offset, name: $0.element, parentId: id)
                       })
    }

    private func tag(_ name: String, count: Int = 500) -> RadioBrowserTag {
        RadioBrowserTag(name: name, stationcount: count)
    }

    // MARK: - Skeleton from the SHOUTcast tree

    @Test func build_mapsShoutcastGenresWithDefaultTag() {
        let union = RadioGenreUnion.build(shoutcastTree: [scGenre("Jazz")], topTags: [])
        #expect(union.count == 1)
        #expect(union[0].name == "Jazz")
        #expect(union[0].shoutcastGenre == "Jazz")
        #expect(union[0].tags == ["jazz"])
    }

    @Test func build_preservesSubgenres() {
        let union = RadioGenreUnion.build(shoutcastTree: [scGenre("Rock", subs: ["Classic Rock", "Punk"])],
                                          topTags: [])
        #expect(union[0].subgenres.map(\.name) == ["Classic Rock", "Punk"])
        #expect(union[0].subgenres[0].shoutcastGenre == "Classic Rock")
        #expect(union[0].subgenres[0].tags == ["classic rock"])
    }

    @Test func build_appliesAliasTable() {
        let union = RadioGenreUnion.build(shoutcastTree: [scGenre("R&B/Urban")], topTags: [])
        #expect(union[0].tags == ["rnb"])
    }

    @Test func build_emptyTree_fallsBackToBundledDefaults() {
        let union = RadioGenreUnion.build(shoutcastTree: [], topTags: [])
        #expect(union.map(\.name) == ShoutcastGenre.bundledDefaults.map(\.name))
    }

    // MARK: - Folding in Radio Browser tags

    @Test func build_coveredTags_areNotDuplicated() {
        let union = RadioGenreUnion.build(shoutcastTree: [scGenre("Rock", subs: ["Punk"])],
                                          topTags: [tag("rock", count: 9000), tag("punk", count: 800)])
        #expect(union.count == 1)
        #expect(union[0].subgenres.map(\.name) == ["Punk"])
    }

    @Test func build_knownTag_foldsUnderMatchingParent() {
        let union = RadioGenreUnion.build(shoutcastTree: [scGenre("Electronic")],
                                          topTags: [tag("synthwave", count: 400)])
        let electronic = union[0]
        #expect(electronic.subgenres.count == 1)
        #expect(electronic.subgenres[0].name == "Synthwave")
        #expect(electronic.subgenres[0].shoutcastGenre == nil)
        #expect(electronic.subgenres[0].tags == ["synthwave"])
    }

    @Test func build_unmappedTag_goesToMoreGenres() {
        let union = RadioGenreUnion.build(shoutcastTree: [scGenre("Rock")],
                                          topTags: [tag("schlager", count: 700)])
        let more = union.last
        #expect(more?.name == "More genres")
        #expect(more?.shoutcastGenre == nil)
        #expect(more?.subgenres.map(\.name) == ["Schlager"])
        #expect(more?.subgenres.first?.tags == ["schlager"])
    }

    @Test func build_multiWordTag_capitalizedForDisplay() {
        let union = RadioGenreUnion.build(shoutcastTree: [scGenre("Pop")],
                                          topTags: [tag("k-pop", count: 600)])
        #expect(union[0].subgenres.map(\.name) == ["K-Pop"])
    }

    @Test func build_tagsBelowThreshold_areDropped() {
        let union = RadioGenreUnion.build(shoutcastTree: [scGenre("Rock")],
                                          topTags: [tag("obscuro", count: 12)],
                                          minStationCount: 100)
        #expect(union.count == 1)
        #expect(union[0].subgenres.isEmpty)
    }

    @Test func build_junkTags_areExcluded() {
        // "music" and "radio" are huge Radio Browser tags but meaningless as genres.
        let union = RadioGenreUnion.build(shoutcastTree: [scGenre("Rock")],
                                          topTags: [tag("music", count: 4900), tag("radio", count: 2100)])
        #expect(union.last?.name == "Rock")
    }

    @Test func build_noMoreGenresEntry_whenNothingLeftOver() {
        let union = RadioGenreUnion.build(shoutcastTree: [scGenre("Rock")],
                                          topTags: [tag("rock", count: 9000)])
        #expect(union.last?.name == "Rock")
    }

    @Test func build_foldedTagParent_missingFromTree_landsInMoreGenres() {
        // "synthwave" maps to Electronic, but the tree has no Electronic genre.
        let union = RadioGenreUnion.build(shoutcastTree: [scGenre("Rock")],
                                          topTags: [tag("synthwave", count: 400)])
        #expect(union.last?.name == "More genres")
        #expect(union.last?.subgenres.map(\.name) == ["Synthwave"])
    }

    // MARK: - Codable (the union tree is cached to disk)

    @Test func codableRoundTrip() throws {
        let union = RadioGenreUnion.build(shoutcastTree: [scGenre("Rock", subs: ["Punk"])],
                                          topTags: [tag("schlager", count: 700)])
        let decoded = try JSONDecoder().decode([RadioGenre].self, from: JSONEncoder().encode(union))
        #expect(decoded == union)
    }
}
