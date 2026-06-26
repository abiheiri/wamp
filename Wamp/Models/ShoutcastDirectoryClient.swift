import Foundation

// MARK: - Protocol

protocol ShoutcastDirectoryAPI {
    func browseByGenre(_ genre: String) async throws -> [ShoutcastStation]
    func search(_ query: String) async throws -> [ShoutcastStation]
    func getStreamURL(for stationID: Int) async throws -> URL
}

// MARK: - Error

enum ShoutcastDirectoryError: Error, Equatable {
    case httpError(statusCode: Int)
    case invalidStreamURL(String)
    case decodingError(Error)

    static func == (lhs: ShoutcastDirectoryError, rhs: ShoutcastDirectoryError) -> Bool {
        switch (lhs, rhs) {
        case let (.httpError(l), .httpError(r)): return l == r
        case let (.invalidStreamURL(l), .invalidStreamURL(r)): return l == r
        case (.decodingError, .decodingError): return true
        default: return false
        }
    }
}

// MARK: - Client

final class ShoutcastDirectoryClient: ShoutcastDirectoryAPI {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared, baseURL: URL = URL(string: "https://directory.shoutcast.com")!) {
        self.session = session
        self.baseURL = baseURL
    }

    /// Fetch stations for a given genre name (e.g. "Rock", "Jazz").
    func browseByGenre(_ genre: String) async throws -> [ShoutcastStation] {
        let url = baseURL.appendingPathComponent("Home/BrowseByGenre")
        let request = Self.formPOST(url: url, body: "genrename=\(genre)")
        return try await performRequest(request)
    }

    /// Search stations by query string.
    func search(_ query: String) async throws -> [ShoutcastStation] {
        let url = baseURL.appendingPathComponent("Search/UpdateSearch")
        let request = Self.formPOST(url: url, body: "query=\(query)")
        return try await performRequest(request)
    }

    /// Resolve the actual stream URL for a station ID.
    func getStreamURL(for stationID: Int) async throws -> URL {
        let url = baseURL.appendingPathComponent("Player/GetStreamUrl")
        let request = Self.formPOST(url: url, body: "station=\(stationID)")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShoutcastDirectoryError.httpError(statusCode: -1)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ShoutcastDirectoryError.httpError(statusCode: httpResponse.statusCode)
        }

        let string = try decoder.decode(String.self, from: data)
        guard !string.isEmpty, let streamURL = URL(string: string) else {
            throw ShoutcastDirectoryError.invalidStreamURL(string)
        }
        return streamURL
    }

    // MARK: - Private

    private func performRequest(_ request: URLRequest) async throws -> [ShoutcastStation] {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShoutcastDirectoryError.httpError(statusCode: -1)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ShoutcastDirectoryError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode([ShoutcastStation].self, from: data)
        } catch {
            throw ShoutcastDirectoryError.decodingError(error)
        }
    }

    private static func formPOST(url: URL, body: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        return request
    }
}
