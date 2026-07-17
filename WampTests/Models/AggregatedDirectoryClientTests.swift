import Testing
import Foundation
@testable import Wamp

// MARK: - Mocks

private final class MockShoutcast: ShoutcastDirectoryAPI {
    var browseResult: Result<[ShoutcastStation], Error> = .success([])
    var searchResult: Result<[ShoutcastStation], Error> = .success([])
    var genreTreeResult: Result<[ShoutcastGenre], Error> = .success([])
    var streamURLResult: Result<URL, Error> = .failure(ShoutcastDirectoryError.invalidStreamURL(""))
    private(set) var browsedGenres: [String] = []
    private(set) var resolvedIDs: [Int] = []

    func browseByGenre(_ genre: String) async throws -> [ShoutcastStation] {
        browsedGenres.append(genre)
        return try browseResult.get()
    }
    func search(_ query: String) async throws -> [ShoutcastStation] { try searchResult.get() }
    func getStreamURL(for stationID: Int) async throws -> URL {
        resolvedIDs.append(stationID)
        return try streamURLResult.get()
    }
    func fetchGenreTree() async throws -> [ShoutcastGenre] { try genreTreeResult.get() }
}

private final class MockRadioBrowser: RadioBrowserAPI {
    var tagResults: [String: Result<[RadioStation], Error>] = [:]
    var searchResult: Result<[RadioStation], Error> = .success([])
    var tagsResult: Result<[RadioBrowserTag], Error> = .success([])
    private(set) var queriedTags: [String] = []
    private(set) var clickedUUIDs: [String] = []

    func stationsByTag(_ tag: String) async throws -> [RadioStation] {
        queriedTags.append(tag)
        return try (tagResults[tag] ?? .success([])).get()
    }
    func searchStations(_ query: String) async throws -> [RadioStation] { try searchResult.get() }
    func fetchTopTags(limit: Int) async throws -> [RadioBrowserTag] { try tagsResult.get() }
    func registerClick(stationUUID: String) async { clickedUUIDs.append(stationUUID) }
}

// MARK: - Helpers

private func scStation(_ id: Int, _ name: String) -> ShoutcastStation {
    ShoutcastStation(id: id, name: name, genre: "Rock", bitrate: 128,
                     listeners: 100, format: "MP3", streamURL: nil)
}

private func rbStation(_ id: String, _ name: String) -> RadioStation {
    RadioStation(id: id, source: .radioBrowser, name: name, genre: "rock", bitrate: 128,
                 popularity: 100, format: "MP3", streamURL: URL(string: "http://x.example/\(id)"))
}

private enum TestError: Error { case boom }

private let rockGenre = RadioGenre(name: "Rock", shoutcastGenre: "Rock", tags: ["rock"])

// MARK: - Tests

@Suite("AggregatedDirectoryClient")
struct AggregatedDirectoryClientTests {

    private func makeClient() -> (AggregatedDirectoryClient, MockShoutcast, MockRadioBrowser) {
        let sc = MockShoutcast()
        let rb = MockRadioBrowser()
        return (AggregatedDirectoryClient(shoutcast: sc, radioBrowser: rb), sc, rb)
    }

    // MARK: - browse

    @Test func browse_mergesBothDirectories() async throws {
        let (client, sc, rb) = makeClient()
        sc.browseResult = .success([scStation(1, "SC One"), scStation(2, "SC Two")])
        rb.tagResults["rock"] = .success([rbStation("u1", "RB One")])

        let result = try await client.browse(rockGenre)

        #expect(result.stations.map(\.name) == ["SC One", "RB One", "SC Two"])
        #expect(result.isPartial == false)
        #expect(sc.browsedGenres == ["Rock"])
        #expect(rb.queriedTags == ["rock"])
    }

    @Test func browse_shoutcastFails_returnsRadioBrowserPartial() async throws {
        let (client, sc, rb) = makeClient()
        sc.browseResult = .failure(TestError.boom)
        rb.tagResults["rock"] = .success([rbStation("u1", "RB One")])

        let result = try await client.browse(rockGenre)

        #expect(result.stations.map(\.name) == ["RB One"])
        #expect(result.isPartial == true)
    }

    @Test func browse_radioBrowserFails_returnsShoutcastPartial() async throws {
        let (client, sc, rb) = makeClient()
        sc.browseResult = .success([scStation(1, "SC One")])
        rb.tagResults["rock"] = .failure(TestError.boom)

        let result = try await client.browse(rockGenre)

        #expect(result.stations.map(\.name) == ["SC One"])
        #expect(result.isPartial == true)
    }

    @Test func browse_bothFail_throws() async {
        let (client, sc, rb) = makeClient()
        sc.browseResult = .failure(TestError.boom)
        rb.tagResults["rock"] = .failure(TestError.boom)

        await #expect(throws: AggregatedDirectoryError.self) {
            _ = try await client.browse(rockGenre)
        }
    }

    @Test func browse_radioBrowserOnlyGenre_skipsShoutcast() async throws {
        let (client, sc, rb) = makeClient()
        rb.tagResults["synthwave"] = .success([rbStation("u1", "Nightride FM")])

        let genre = RadioGenre(name: "Synthwave", shoutcastGenre: nil, tags: ["synthwave"])
        let result = try await client.browse(genre)

        #expect(result.stations.map(\.name) == ["Nightride FM"])
        #expect(result.isPartial == false)
        #expect(sc.browsedGenres.isEmpty)
    }

    @Test func browse_multiTagGenre_queriesEachTag() async throws {
        let (client, _, rb) = makeClient()
        rb.tagResults["80s"] = .success([rbStation("u1", "Eighties FM")])
        rb.tagResults["90s"] = .success([rbStation("u2", "Nineties FM")])

        let genre = RadioGenre(name: "Decades", shoutcastGenre: nil, tags: ["80s", "90s"])
        let result = try await client.browse(genre)

        #expect(Set(rb.queriedTags) == ["80s", "90s"])
        #expect(result.stations.count == 2)
    }

    @Test func browse_oneTagOfSeveralFails_stillSucceeds() async throws {
        let (client, _, rb) = makeClient()
        rb.tagResults["80s"] = .failure(TestError.boom)
        rb.tagResults["90s"] = .success([rbStation("u2", "Nineties FM")])

        let genre = RadioGenre(name: "Decades", shoutcastGenre: nil, tags: ["80s", "90s"])
        let result = try await client.browse(genre)

        #expect(result.stations.map(\.name) == ["Nineties FM"])
    }

    // MARK: - search

    @Test func search_mergesBothDirectories() async throws {
        let (client, sc, rb) = makeClient()
        sc.searchResult = .success([scStation(1, "SC Jazz")])
        rb.searchResult = .success([rbStation("u1", "RB Jazz")])

        let result = try await client.search("jazz")

        #expect(result.stations.map(\.name) == ["SC Jazz", "RB Jazz"])
        #expect(result.isPartial == false)
    }

    @Test func search_oneSideFails_partialResults() async throws {
        let (client, sc, rb) = makeClient()
        sc.searchResult = .failure(TestError.boom)
        rb.searchResult = .success([rbStation("u1", "RB Jazz")])

        let result = try await client.search("jazz")

        #expect(result.stations.map(\.name) == ["RB Jazz"])
        #expect(result.isPartial == true)
    }

    // MARK: - fetchGenres

    @Test func fetchGenres_buildsUnionFromBothSources() async throws {
        let (client, sc, rb) = makeClient()
        sc.genreTreeResult = .success([ShoutcastGenre(id: 1, name: "Electronic", parentId: 0)])
        rb.tagsResult = .success([RadioBrowserTag(name: "synthwave", stationcount: 400)])

        let genres = try await client.fetchGenres()

        #expect(genres.first?.name == "Electronic")
        #expect(genres.first?.subgenres.map(\.name) == ["Synthwave"])
    }

    @Test func fetchGenres_shoutcastDown_usesBundledSkeletonPlusTags() async throws {
        let (client, sc, rb) = makeClient()
        sc.genreTreeResult = .failure(TestError.boom)
        rb.tagsResult = .success([RadioBrowserTag(name: "anime", stationcount: 700)])

        let genres = try await client.fetchGenres()

        #expect(genres.first?.name == ShoutcastGenre.bundledDefaults.first?.name)
        #expect(genres.last?.name == "More genres")
    }

    @Test func fetchGenres_bothDown_throws() async {
        let (client, sc, rb) = makeClient()
        sc.genreTreeResult = .failure(TestError.boom)
        rb.tagsResult = .failure(TestError.boom)

        await #expect(throws: AggregatedDirectoryError.self) {
            _ = try await client.fetchGenres()
        }
    }

    // MARK: - Stream resolution

    @Test func resolveStreamURL_passesThroughExistingURL() async throws {
        let (client, sc, _) = makeClient()
        let station = rbStation("u1", "RB One")
        let url = try await client.resolveStreamURL(for: station)
        #expect(url == station.streamURL)
        #expect(sc.resolvedIDs.isEmpty)
    }

    @Test func resolveStreamURL_resolvesShoutcastByNumericID() async throws {
        let (client, sc, _) = makeClient()
        sc.streamURLResult = .success(URL(string: "http://185.33.21.112/stream")!)

        let station = RadioStation(from: scStation(1552431, "Rock Classics"))
        let url = try await client.resolveStreamURL(for: station)

        #expect(url.absoluteString == "http://185.33.21.112/stream")
        #expect(sc.resolvedIDs == [1552431])
    }

    @Test func resolveStreamURL_unresolvable_throws() async {
        let (client, _, _) = makeClient()
        let broken = RadioStation(id: "u9", source: .radioBrowser, name: "No URL", genre: "",
                                  bitrate: 0, popularity: 0, format: "MP3", streamURL: nil)
        await #expect(throws: AggregatedDirectoryError.self) {
            _ = try await client.resolveStreamURL(for: broken)
        }
    }

    // MARK: - Click ping

    @Test func stationWillPlay_pingsRadioBrowserStationsOnly() async {
        let (client, _, rb) = makeClient()
        await client.stationWillPlay(rbStation("u1", "RB One"))
        await client.stationWillPlay(RadioStation(from: scStation(1, "SC One")))
        #expect(rb.clickedUUIDs == ["u1"])
    }
}
