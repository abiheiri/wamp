import Testing
import Foundation
@testable import Wamp

@Suite("ShoutcastGenre")
struct ShoutcastGenreTests {

    // Mirrors the directory homepage markup: each genre is an onclick call
    // loadStationsByGenre('Name', id, parentId) — parentId 0 means top-level.
    private let sampleHTML = """
    <ul>
      <li><a onclick="return loadStationsByGenre('Alternative', 1, 0);">Alternative</a></li>
      <li><a onclick="return loadStationsByGenre('Adult Alternative', 2, 1);">Adult Alternative</a></li>
      <li><a onclick="return loadStationsByGenre('Britpop', 3, 1);">Britpop</a></li>
      <li><a onclick="return loadStationsByGenre('Rock', 25, 0);">Rock</a></li>
      <li><a onclick="return loadStationsByGenre('Classic Rock', 26, 25);">Classic Rock</a></li>
      <li><a onclick="return loadStationsByGenre('R&amp;B', 40, 0);">R&amp;B</a></li>
    </ul>
    """

    // MARK: - Parse

    @Test func parse_extractsAllGenresWithIdsAndParents() {
        let genres = ShoutcastGenre.parse(html: sampleHTML)
        #expect(genres.count == 6)
        let alt = genres.first { $0.id == 1 }
        #expect(alt?.name == "Alternative")
        #expect(alt?.parentId == 0)
        let adult = genres.first { $0.id == 2 }
        #expect(adult?.name == "Adult Alternative")
        #expect(adult?.parentId == 1)
    }

    @Test func parse_deduplicatesById() {
        let dupe = sampleHTML + "\n<a onclick=\"return loadStationsByGenre('Rock', 25, 0);\">Rock</a>"
        let genres = ShoutcastGenre.parse(html: dupe)
        #expect(genres.filter { $0.id == 25 }.count == 1)
    }

    @Test func parse_emptyOrJunk_returnsEmpty() {
        #expect(ShoutcastGenre.parse(html: "<html>no genres here</html>").isEmpty)
        #expect(ShoutcastGenre.parse(html: "").isEmpty)
    }

    // MARK: - Tree

    @Test func buildTree_groupsSubgenresUnderTopLevel() {
        let tree = ShoutcastGenre.buildTree(from: ShoutcastGenre.parse(html: sampleHTML))
        // Top-level genres only (Alternative, Rock, R&B).
        #expect(tree.map(\.id).sorted() == [1, 25, 40])
        let alt = tree.first { $0.id == 1 }
        #expect(alt?.subgenres.map(\.name).sorted() == ["Adult Alternative", "Britpop"])
        let rock = tree.first { $0.id == 25 }
        #expect(rock?.subgenres.map(\.name) == ["Classic Rock"])
        let rnb = tree.first { $0.id == 40 }
        #expect(rnb?.subgenres.isEmpty == true)
    }

    @Test func bundledDefaults_areTopLevelAndNonEmpty() {
        #expect(!ShoutcastGenre.bundledDefaults.isEmpty)
        #expect(ShoutcastGenre.bundledDefaults.allSatisfy { $0.parentId == 0 })
    }

    // MARK: - Listener abbreviation

    @Test func abbreviatedListeners() {
        #expect(ShoutcastStation.abbreviateListeners(0) == "0")
        #expect(ShoutcastStation.abbreviateListeners(950) == "950")
        #expect(ShoutcastStation.abbreviateListeners(5809) == "5.8K")
        #expect(ShoutcastStation.abbreviateListeners(12000) == "12K")
        #expect(ShoutcastStation.abbreviateListeners(1_500_000) == "1.5M")
    }
}
