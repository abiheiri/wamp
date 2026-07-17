import Foundation
import Combine

/// Owns the combined station list shown in the playlist panel's Radio tab and
/// drives stream playback through `AudioEngine`. Parallel to `PlaylistManager`,
/// but for remote stations — the local playlist never holds streams. Talks to
/// one `RadioDirectoryAPI` (the SHOUTcast + Radio Browser aggregator), so
/// nothing at this layer knows two directories exist.
final class RadioManager: ObservableObject {
    @Published private(set) var stations: [RadioStation] = []
    @Published var searchQuery: String = ""
    /// ID of the station currently selected/playing, so the UI can highlight it
    /// and next/prev can locate its position regardless of the active filter.
    @Published private(set) var currentStationID: String?
    @Published private(set) var statusMessage: String = "Pick a genre and load"
    @Published private(set) var isLoading = false
    /// Combined genre tree for the picker. Starts with the offline union (the
    /// bundled SHOUTcast genres, no tag fold-ins) so the menu is never empty,
    /// then upgrades to the live (or cached) tree.
    @Published private(set) var genres: [RadioGenre] = RadioManager.defaultGenres
    /// User-saved stations, persisted to disk and shown via the genre menu's
    /// "★ Favorites" entry.
    @Published private(set) var favorites: [RadioStation] = []

    /// Offline fallback menu: bundled genre skeleton, no live tags.
    static let defaultGenres = RadioGenreUnion.build(shoutcastTree: [], topTags: [])

    private weak var audioEngine: AudioEngine?
    private let client: RadioDirectoryAPI

    /// True once a live genre fetch has succeeded this session (skip re-fetching).
    private var hasLiveGenres = false
    private var isLoadingGenres = false
    /// Whether the station list is currently showing favorites (vs a genre/search),
    /// so removing a favorite refreshes the view in place.
    private var viewingFavorites = false

    private static let appDir: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Wamp")
    /// On-disk cache of the last good genre tree, in the same dir as other state.
    private let genreCacheURL = RadioManager.appDir.appendingPathComponent("genres.json")
    private let favoritesURL = RadioManager.appDir.appendingPathComponent("favorites.json")

    init(client: RadioDirectoryAPI = AggregatedDirectoryClient()) {
        self.client = client
        favorites = loadFavorites()
    }

    func setAudioEngine(_ engine: AudioEngine) {
        self.audioEngine = engine
    }

    // MARK: - Derived

    var filteredStations: [RadioStation] {
        Self.filter(stations, query: searchQuery)
    }

    /// The full station object currently (or most recently) played — retained
    /// even when it came from the ephemeral Cmd+J finder and isn't in `stations`.
    @Published private(set) var nowPlayingStation: RadioStation?

    var currentStation: RadioStation? {
        nowPlayingStation ?? stations.first { $0.id == currentStationID }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Case-insensitive filter on station name or genre. Blank query returns all.
    static func filter(_ stations: [RadioStation], query: String) -> [RadioStation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return stations }
        return stations.filter {
            $0.name.lowercased().contains(q) || $0.genre.lowercased().contains(q)
        }
    }

    /// Station `offset` positions from the one identified by `currentID`, wrapping
    /// around the list. Falls back to the first station when `currentID` is nil or
    /// absent. Returns nil only for an empty list.
    static func adjacentStation(to currentID: String?, in list: [RadioStation], offset: Int) -> RadioStation? {
        guard !list.isEmpty else { return nil }
        guard let currentID, let idx = list.firstIndex(where: { $0.id == currentID }) else {
            return list.first
        }
        let count = list.count
        let next = ((idx + offset) % count + count) % count
        return list[next]
    }

    // MARK: - Directory loading

    @MainActor
    func loadGenre(_ genre: RadioGenre) async {
        guard !isLoading else { return }
        isLoading = true
        viewingFavorites = false
        statusMessage = "Loading \(genre.name)…"
        do {
            let result = try await client.browse(genre)
            stations = result.stations
            statusMessage = Self.statusForList(count: stations.count, label: genre.name,
                                               isPartial: result.isPartial)
        } catch {
            stations = []
            statusMessage = "Failed to load \(genre.name)"
        }
        isLoading = false
    }

    @MainActor
    func search(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isLoading else { return }
        isLoading = true
        viewingFavorites = false
        // A directory-wide search returns its own result set — clear the local
        // text filter so those results aren't narrowed again by the typed query.
        searchQuery = ""
        statusMessage = "Searching…"
        do {
            let result = try await client.search(q)
            stations = result.stations
            statusMessage = stations.isEmpty
                ? "No results for \"\(q)\""
                : Self.statusForList(count: stations.count, label: "\"\(q)\"",
                                     isPartial: result.isPartial)
        } catch {
            stations = []
            statusMessage = "Search failed"
        }
        isLoading = false
    }

    /// "84 stations in Rock", with a compact partial marker when one directory
    /// was unreachable. Width is precious — the status line is ~275px.
    private static func statusForList(count: Int, label: String, isPartial: Bool) -> String {
        guard count > 0 else { return "No stations in \(label)" }
        return "\(count) stations in \(label)" + (isPartial ? " (partial)" : "")
    }

    /// Directory-wide search that returns results without mutating the panel's
    /// station list or status. Used by the Cmd+J finder so its Radio tab stays
    /// ephemeral (the panel keeps showing whatever genre you were browsing).
    func searchStations(_ query: String) async throws -> [RadioStation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return try await client.search(q).stations
    }

    // MARK: - Genre tree (lazy, cached, with fallback)

    /// Loads the genre tree the first time the Radio tab is opened: disk cache for
    /// an instant menu, then a live refresh. Falls back to the cache or the bundled
    /// defaults if neither directory is reachable. Safe to call repeatedly.
    @MainActor
    func loadGenresIfNeeded() async {
        guard !hasLiveGenres, !isLoadingGenres else { return }
        isLoadingGenres = true
        defer { isLoadingGenres = false }

        // Show cached genres immediately (only if we're still on the defaults).
        if genres == Self.defaultGenres, let cached = loadCachedGenres(), !cached.isEmpty {
            genres = cached
        }

        do {
            let fresh = try await client.fetchGenres()
            if !fresh.isEmpty {
                genres = fresh
                hasLiveGenres = true
                saveCachedGenres(fresh)
            }
        } catch {
            // Offline — keep whatever we have (cache or defaults).
        }
    }

    private func loadCachedGenres() -> [RadioGenre]? {
        // A pre-aggregator cache holds [ShoutcastGenre] and fails to decode
        // here, which quietly discards it — the next live fetch rewrites it.
        guard let data = try? Data(contentsOf: genreCacheURL) else { return nil }
        return try? JSONDecoder().decode([RadioGenre].self, from: data)
    }

    private func saveCachedGenres(_ tree: [RadioGenre]) {
        guard let data = try? JSONEncoder().encode(tree) else { return }
        try? FileManager.default.createDirectory(
            at: genreCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: genreCacheURL)
    }

    // MARK: - Favorites

    /// Pure add-or-remove by station id (toggle semantics) — unit-tested.
    static func toggledFavorites(_ favorites: [RadioStation],
                                 toggling station: RadioStation) -> [RadioStation] {
        if favorites.contains(where: { $0.id == station.id }) {
            return favorites.filter { $0.id != station.id }
        }
        return favorites + [station]
    }

    func isFavorite(_ station: RadioStation) -> Bool {
        favorites.contains { $0.id == station.id }
    }

    /// Add the station to favorites, or remove it if already saved. Persists, and
    /// refreshes the list in place when the favorites view is showing.
    @MainActor
    func toggleFavorite(_ station: RadioStation) {
        favorites = Self.toggledFavorites(favorites, toggling: station)
        saveFavorites(favorites)
        if viewingFavorites {
            stations = favorites
            statusMessage = favorites.isEmpty ? "No favorites yet" : "\(favorites.count) favorites"
        }
    }

    /// Show the saved favorites in the station list.
    @MainActor
    func showFavorites() {
        viewingFavorites = true
        searchQuery = ""
        stations = favorites
        statusMessage = favorites.isEmpty ? "No favorites yet" : "\(favorites.count) favorites"
    }

    private func loadFavorites() -> [RadioStation] {
        // decodeFavorites migrates the legacy [ShoutcastStation] file in place.
        guard let data = try? Data(contentsOf: favoritesURL),
              let list = RadioStation.decodeFavorites(data) else { return [] }
        return list
    }

    private func saveFavorites(_ list: [RadioStation]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? FileManager.default.createDirectory(
            at: favoritesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: favoritesURL)
    }

    // MARK: - Playback

    /// Resolve a station's stream URL (if not already resolved) and start playing.
    /// The connecting / playing / error state shown in the player marquee is driven
    /// by `AudioEngine.streamPhase`; this just kicks it off.
    @MainActor
    func playStation(_ station: RadioStation) async {
        currentStationID = station.id
        nowPlayingStation = station
        // Show "Connecting…" and stop current audio immediately, before the
        // (possibly slow) directory lookup resolves the real stream URL.
        audioEngine?.beginStreamConnecting()
        do {
            let url = try await client.resolveStreamURL(for: station)
            // A newer click may have superseded this one while the URL resolved
            // (obscure stations resolve slowly) — don't let a stale request win.
            guard currentStationID == station.id else { return }
            audioEngine?.playStream(url: url)
            // Popularity ping (Radio Browser only) — fire-and-forget.
            let client = self.client
            Task.detached { await client.stationWillPlay(station) }
        } catch {
            guard currentStationID == station.id else { return }
            audioEngine?.reportStreamFailure("Couldn't connect to \(station.name)")
        }
    }

    /// Play the next station in the visible (filtered) list, wrapping around.
    @MainActor
    func playNext() async {
        guard let next = Self.adjacentStation(to: currentStationID, in: filteredStations, offset: 1) else { return }
        await playStation(next)
    }

    /// Play the previous station in the visible (filtered) list, wrapping around.
    @MainActor
    func playPrevious() async {
        guard let prev = Self.adjacentStation(to: currentStationID, in: filteredStations, offset: -1) else { return }
        await playStation(prev)
    }
}
