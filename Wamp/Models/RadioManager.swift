import Foundation
import Combine

/// Owns the SHOUTcast station list shown in the playlist panel's Radio tab and
/// drives stream playback through `AudioEngine`. Parallel to `PlaylistManager`,
/// but for remote stations — the local playlist never holds streams.
final class RadioManager: ObservableObject {
    @Published private(set) var stations: [ShoutcastStation] = []
    @Published var searchQuery: String = ""
    /// ID of the station currently selected/playing, so the UI can highlight it
    /// and next/prev can locate its position regardless of the active filter.
    @Published private(set) var currentStationID: Int?
    @Published private(set) var statusMessage: String = "Pick a genre and load"
    @Published private(set) var isLoading = false
    /// Main/sub genre tree for the picker. Starts with the bundled defaults so the
    /// menu is never empty, then upgrades to the live (or cached) directory tree.
    @Published private(set) var genres: [ShoutcastGenre] = ShoutcastGenre.bundledDefaults
    /// User-saved stations, persisted to disk and shown via the genre menu's
    /// "★ Favorites" entry.
    @Published private(set) var favorites: [ShoutcastStation] = []

    private weak var audioEngine: AudioEngine?
    private let client: ShoutcastDirectoryAPI

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

    init(client: ShoutcastDirectoryAPI = ShoutcastDirectoryClient()) {
        self.client = client
        favorites = loadFavorites()
    }

    func setAudioEngine(_ engine: AudioEngine) {
        self.audioEngine = engine
    }

    // MARK: - Derived

    var filteredStations: [ShoutcastStation] {
        Self.filter(stations, query: searchQuery)
    }

    var currentStation: ShoutcastStation? {
        guard let id = currentStationID else { return nil }
        return stations.first { $0.id == id }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Case-insensitive filter on station name or genre. Blank query returns all.
    static func filter(_ stations: [ShoutcastStation], query: String) -> [ShoutcastStation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return stations }
        return stations.filter {
            $0.name.lowercased().contains(q) || $0.genre.lowercased().contains(q)
        }
    }

    /// Station `offset` positions from the one identified by `currentID`, wrapping
    /// around the list. Falls back to the first station when `currentID` is nil or
    /// absent. Returns nil only for an empty list.
    static func adjacentStation(to currentID: Int?, in list: [ShoutcastStation], offset: Int) -> ShoutcastStation? {
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
    func loadGenre(_ genre: String) async {
        guard !isLoading else { return }
        isLoading = true
        viewingFavorites = false
        statusMessage = "Loading \(genre)…"
        do {
            stations = try await client.browseByGenre(genre)
            statusMessage = stations.isEmpty ? "No stations in \(genre)" : "\(stations.count) stations in \(genre)"
        } catch {
            stations = []
            statusMessage = "Failed to load \(genre)"
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
            stations = try await client.search(q)
            statusMessage = stations.isEmpty ? "No results for \"\(q)\"" : "\(stations.count) results for \"\(q)\""
        } catch {
            stations = []
            statusMessage = "Search failed"
        }
        isLoading = false
    }

    // MARK: - Genre tree (lazy, cached, with fallback)

    /// Loads the genre tree the first time the Radio tab is opened: disk cache for
    /// an instant menu, then a live refresh. Falls back to the cache or the bundled
    /// defaults if the directory is unreachable. Safe to call repeatedly.
    @MainActor
    func loadGenresIfNeeded() async {
        guard !hasLiveGenres, !isLoadingGenres else { return }
        isLoadingGenres = true
        defer { isLoadingGenres = false }

        // Show cached genres immediately (only if we're still on bundled defaults).
        if genres == ShoutcastGenre.bundledDefaults, let cached = loadCachedGenres(), !cached.isEmpty {
            genres = cached
        }

        do {
            let fresh = try await client.fetchGenreTree()
            if !fresh.isEmpty {
                genres = fresh
                hasLiveGenres = true
                saveCachedGenres(fresh)
            }
        } catch {
            // Offline or markup changed — keep whatever we have (cache or defaults).
        }
    }

    private func loadCachedGenres() -> [ShoutcastGenre]? {
        guard let data = try? Data(contentsOf: genreCacheURL) else { return nil }
        return try? JSONDecoder().decode([ShoutcastGenre].self, from: data)
    }

    private func saveCachedGenres(_ tree: [ShoutcastGenre]) {
        guard let data = try? JSONEncoder().encode(tree) else { return }
        try? FileManager.default.createDirectory(
            at: genreCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: genreCacheURL)
    }

    // MARK: - Favorites

    /// Pure add-or-remove by station id (toggle semantics) — unit-tested.
    static func toggledFavorites(_ favorites: [ShoutcastStation],
                                 toggling station: ShoutcastStation) -> [ShoutcastStation] {
        if favorites.contains(where: { $0.id == station.id }) {
            return favorites.filter { $0.id != station.id }
        }
        return favorites + [station]
    }

    func isFavorite(_ station: ShoutcastStation) -> Bool {
        favorites.contains { $0.id == station.id }
    }

    /// Add the station to favorites, or remove it if already saved. Persists, and
    /// refreshes the list in place when the favorites view is showing.
    @MainActor
    func toggleFavorite(_ station: ShoutcastStation) {
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

    private func loadFavorites() -> [ShoutcastStation] {
        guard let data = try? Data(contentsOf: favoritesURL),
              let list = try? JSONDecoder().decode([ShoutcastStation].self, from: data) else { return [] }
        return list
    }

    private func saveFavorites(_ list: [ShoutcastStation]) {
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
    func playStation(_ station: ShoutcastStation) async {
        currentStationID = station.id
        // Show "Connecting…" and stop current audio immediately, before the
        // (possibly slow) directory lookup resolves the real stream URL.
        audioEngine?.beginStreamConnecting()
        do {
            let url: URL
            if let resolved = station.streamURL {
                url = resolved
            } else {
                url = try await client.getStreamURL(for: station.id)
            }
            audioEngine?.playStream(url: url)
        } catch {
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
