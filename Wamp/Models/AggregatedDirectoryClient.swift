import Foundation

// MARK: - Protocol

/// Stations returned by a directory query, with a flag for degraded results.
struct DirectoryResult: Equatable {
    let stations: [RadioStation]
    /// True when one directory failed and the list only covers the other.
    let isPartial: Bool
}

/// The directory surface `RadioManager` talks to. One implementation today —
/// the aggregator — but the seam keeps the manager testable and source-blind.
protocol RadioDirectoryAPI {
    func browse(_ genre: RadioGenre) async throws -> DirectoryResult
    func search(_ query: String) async throws -> DirectoryResult
    func fetchGenres() async throws -> [RadioGenre]
    func resolveStreamURL(for station: RadioStation) async throws -> URL
    /// Directory bookkeeping when a station starts playing (popularity pings).
    func stationWillPlay(_ station: RadioStation) async
}

// MARK: - Error

enum AggregatedDirectoryError: Error, Equatable {
    /// Every applicable directory failed — nothing to show.
    case allDirectoriesFailed
    /// Station has no stream URL and no way to resolve one.
    case unresolvableStation(String)
}

// MARK: - Client

/// Fans every query out to SHOUTcast and Radio Browser concurrently and merges
/// the answers into one list, so the UI never knows two directories exist.
/// A single directory failing degrades to partial results instead of an error.
final class AggregatedDirectoryClient: RadioDirectoryAPI {
    private let shoutcast: ShoutcastDirectoryAPI
    private let radioBrowser: RadioBrowserAPI

    init(shoutcast: ShoutcastDirectoryAPI = ShoutcastDirectoryClient(),
         radioBrowser: RadioBrowserAPI = RadioBrowserClient()) {
        self.shoutcast = shoutcast
        self.radioBrowser = radioBrowser
    }

    func browse(_ genre: RadioGenre) async throws -> DirectoryResult {
        async let scSide = shoutcastStations(genre: genre.shoutcastGenre)
        async let rbSide = radioBrowserStations(tags: genre.tags)
        return try Self.combine(await scSide, await rbSide)
    }

    func search(_ query: String) async throws -> DirectoryResult {
        async let scSide = capture { try await self.shoutcast.search(query).map(RadioStation.init(from:)) }
        async let rbSide = capture { try await self.radioBrowser.searchStations(query) }
        return try Self.combine(await scSide, await rbSide)
    }

    /// Builds the combined genre menu. Either source may be down — the union
    /// builder falls back to the bundled skeleton and/or skips the tag fold-in.
    /// Throws only when both are unreachable, so callers keep their cache.
    func fetchGenres() async throws -> [RadioGenre] {
        async let treeSide = capture { try await self.shoutcast.fetchGenreTree() }
        async let tagsSide = capture { try await self.radioBrowser.fetchTopTags(limit: 100) }
        let (tree, tags) = (await treeSide, await tagsSide)

        guard (try? tree.get()) != nil || (try? tags.get()) != nil else {
            throw AggregatedDirectoryError.allDirectoriesFailed
        }
        return RadioGenreUnion.build(shoutcastTree: (try? tree.get()) ?? [],
                                     topTags: (try? tags.get()) ?? [])
    }

    /// Radio Browser stations come pre-resolved; SHOUTcast stations may need a
    /// directory round-trip to turn their numeric ID into a stream URL.
    func resolveStreamURL(for station: RadioStation) async throws -> URL {
        if let url = station.streamURL { return url }
        if let scID = station.shoutcastID {
            return try await shoutcast.getStreamURL(for: scID)
        }
        throw AggregatedDirectoryError.unresolvableStation(station.name)
    }

    func stationWillPlay(_ station: RadioStation) async {
        guard station.source == .radioBrowser else { return }
        await radioBrowser.registerClick(stationUUID: station.id)
    }

    // MARK: - Private

    private func capture<T>(_ work: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) }
        catch { return .failure(error) }
    }

    /// nil = this directory doesn't carry the genre (not a failure).
    private func shoutcastStations(genre: String?) async -> Result<[RadioStation], Error>? {
        guard let genre else { return nil }
        return await capture { try await self.shoutcast.browseByGenre(genre).map(RadioStation.init(from:)) }
    }

    /// Queries every tag; one bad tag doesn't fail the side as long as another
    /// answered. nil when the genre has no Radio Browser tags.
    private func radioBrowserStations(tags: [String]) async -> Result<[RadioStation], Error>? {
        guard !tags.isEmpty else { return nil }
        var stations: [RadioStation] = []
        var lastError: Error?
        var anySucceeded = false
        for tag in tags {
            do {
                stations += try await radioBrowser.stationsByTag(tag)
                anySucceeded = true
            } catch {
                lastError = error
            }
        }
        if !anySucceeded, let lastError { return .failure(lastError) }
        return .success(stations)
    }

    /// Merges the two sides. A nil side wasn't applicable; a failed side makes
    /// the result partial; both applicable sides failing is an error.
    private static func combine(_ sc: Result<[RadioStation], Error>?,
                                _ rb: Result<[RadioStation], Error>?) throws -> DirectoryResult {
        let applicable = [sc, rb].compactMap { $0 }
        let successes = applicable.compactMap { try? $0.get() }
        guard applicable.isEmpty || !successes.isEmpty else {
            throw AggregatedDirectoryError.allDirectoriesFailed
        }
        let merged = RadioStationMerger.merged((try? sc?.get()) ?? [], (try? rb?.get()) ?? [])
        return DirectoryResult(stations: merged, isPartial: successes.count < applicable.count)
    }
}
