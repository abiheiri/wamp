import Foundation

// MARK: - Protocol

protocol RadioBrowserAPI {
    func stationsByTag(_ tag: String) async throws -> [RadioStation]
    func searchStations(_ query: String) async throws -> [RadioStation]
    func fetchTopTags(limit: Int) async throws -> [RadioBrowserTag]
    func registerClick(stationUUID: String) async
}

// MARK: - Models

/// A community tag from the Radio Browser directory (its genre equivalent).
struct RadioBrowserTag: Codable, Equatable {
    let name: String
    let stationcount: Int
}

// MARK: - Error

enum RadioBrowserError: Error, Equatable {
    case httpError(statusCode: Int)
    case decodingError(String)
    case allMirrorsFailed
}

// MARK: - Client

/// Client for the community radio-browser.info directory. The service is a set
/// of mirrored servers; every request walks the mirror list until one answers,
/// so a single dead mirror never breaks browsing.
final class RadioBrowserClient: RadioBrowserAPI {
    private let session: URLSession
    private let mirrors: [URL]
    private let decoder = JSONDecoder()
    /// Radio Browser asks clients to identify themselves; generic agents may be throttled.
    private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "Wamp/\(version)"
    }()

    static let defaultMirrors = [
        URL(string: "https://de1.api.radio-browser.info")!,
        URL(string: "https://at1.api.radio-browser.info")!,
        URL(string: "https://nl1.api.radio-browser.info")!,
    ]

    /// Mirrors are shuffled per instance to spread load, per the API guidelines.
    init(session: URLSession = .shared, mirrors: [URL] = defaultMirrors.shuffled()) {
        self.session = session
        self.mirrors = mirrors
    }

    /// Stations carrying the exact tag, most-clicked first.
    func stationsByTag(_ tag: String) async throws -> [RadioStation] {
        let data = try await get(
            path: "json/stations/bytagexact/\(tag.lowercased())",
            query: [
                URLQueryItem(name: "order", value: "clickcount"),
                URLQueryItem(name: "reverse", value: "true"),
                URLQueryItem(name: "hidebroken", value: "true"),
                URLQueryItem(name: "limit", value: "200"),
            ])
        return try decodeStations(data)
    }

    /// Directory-wide station search by name, most-clicked first.
    func searchStations(_ query: String) async throws -> [RadioStation] {
        let data = try await get(
            path: "json/stations/search",
            query: [
                URLQueryItem(name: "name", value: query),
                URLQueryItem(name: "order", value: "clickcount"),
                URLQueryItem(name: "reverse", value: "true"),
                URLQueryItem(name: "hidebroken", value: "true"),
                URLQueryItem(name: "limit", value: "200"),
            ])
        return try decodeStations(data)
    }

    /// The most-used tags in the directory, biggest first.
    func fetchTopTags(limit: Int) async throws -> [RadioBrowserTag] {
        let data = try await get(
            path: "json/tags",
            query: [
                URLQueryItem(name: "order", value: "stationcount"),
                URLQueryItem(name: "reverse", value: "true"),
                URLQueryItem(name: "limit", value: "\(limit)"),
            ])
        do {
            return try decoder.decode([RadioBrowserTag].self, from: data)
        } catch {
            throw RadioBrowserError.decodingError("\(error)")
        }
    }

    /// Tell the directory a station was played, so community popularity ranking
    /// stays meaningful. Fire-and-forget: failures are irrelevant to playback.
    func registerClick(stationUUID: String) async {
        _ = try? await get(path: "json/url/\(stationUUID)", query: [])
    }

    // MARK: - Private

    /// Raw station shape from the API; mapped to `RadioStation` after filtering
    /// out entries with no usable stream URL or a blank name.
    private struct APIStation: Decodable {
        let stationuuid: String
        let name: String
        let url: String
        let url_resolved: String
        let tags: String
        let codec: String
        let bitrate: Int
        let clickcount: Int
    }

    private func decodeStations(_ data: Data) throws -> [RadioStation] {
        let raw: [APIStation]
        do {
            raw = try decoder.decode([APIStation].self, from: data)
        } catch {
            throw RadioBrowserError.decodingError("\(error)")
        }
        return raw.compactMap { api in
            let name = api.name.trimmingCharacters(in: .whitespacesAndNewlines)
            // `url_resolved` is the directory's server-side playlist resolution;
            // fall back to the raw URL when it's blank.
            let urlString = api.url_resolved.isEmpty ? api.url : api.url_resolved
            guard !name.isEmpty, !urlString.isEmpty, let streamURL = URL(string: urlString) else {
                return nil
            }
            return RadioStation(id: api.stationuuid,
                                source: .radioBrowser,
                                name: name,
                                genre: api.tags,
                                bitrate: api.bitrate,
                                popularity: api.clickcount,
                                format: api.codec.uppercased(),
                                streamURL: streamURL)
        }
    }

    /// GET `path` from the first mirror that answers 2xx.
    private func get(path: String, query: [URLQueryItem]) async throws -> Data {
        var lastError: Error = RadioBrowserError.allMirrorsFailed
        for mirror in mirrors {
            var comps = URLComponents(url: mirror.appendingPathComponent(path),
                                      resolvingAgainstBaseURL: false)!
            if !query.isEmpty { comps.queryItems = query }
            var request = URLRequest(url: comps.url!)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw RadioBrowserError.httpError(statusCode: -1)
                }
                guard (200...299).contains(http.statusCode) else {
                    throw RadioBrowserError.httpError(statusCode: http.statusCode)
                }
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
