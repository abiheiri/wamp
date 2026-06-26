import Testing
import Foundation
@testable import Wamp

// MARK: - Mock URLProtocol

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func mockResponse(statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://directory.shoutcast.com")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

private let validStationJSON = """
[
    {
        "ID": 1552431,
        "Name": "Rock Classics",
        "Genre": "Rock",
        "Bitrate": 64,
        "Listeners": 10,
        "Format": "audio/mpeg",
        "StreamUrl": null
    },
    {
        "ID": 99498012,
        "Name": "ROCK ANTENNE",
        "Genre": "Rock",
        "Bitrate": 192,
        "Listeners": 500,
        "Format": "audio/mpeg",
        "StreamUrl": null
    }
]
""".data(using: .utf8)!

// MARK: - Tests

@MainActor
@Suite("ShoutcastDirectoryClient", .serialized)
struct ShoutcastDirectoryClientTests {

    // MARK: - browseByGenre

    @Test func browseByGenre_parsesStations() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/Home/BrowseByGenre")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
            #expect(body == "genrename=Rock")
            return (mockResponse(), validStationJSON)
        }

        let client = ShoutcastDirectoryClient(session: makeMockSession())
        let stations = try await client.browseByGenre("Rock")

        #expect(stations.count == 2)
        #expect(stations[0].id == 1552431)
        #expect(stations[0].name == "Rock Classics")
        #expect(stations[0].format == "audio/mpeg")
        #expect(stations[1].id == 99498012)
    }

    @Test func browseByGenre_emptyResult() async throws {
        MockURLProtocol.requestHandler = { _ in
            (mockResponse(), Data("[]".utf8))
        }

        let client = ShoutcastDirectoryClient(session: makeMockSession())
        let stations = try await client.browseByGenre("Nonexistent")

        #expect(stations.isEmpty)
    }

    @Test func browseByGenre_httpError() async {
        MockURLProtocol.requestHandler = { _ in
            (mockResponse(statusCode: 500), Data())
        }

        let client = ShoutcastDirectoryClient(session: makeMockSession())
        await #expect(throws: ShoutcastDirectoryError.self) {
            try await client.browseByGenre("Rock")
        }
    }

    // MARK: - search

    @Test func search_parsesStations() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/Search/UpdateSearch")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
            #expect(body == "query=Jazz")
            return (mockResponse(), validStationJSON)
        }

        let client = ShoutcastDirectoryClient(session: makeMockSession())
        let stations = try await client.search("Jazz")

        #expect(stations.count == 2)
        #expect(stations[0].name == "Rock Classics")
    }

    @Test func search_emptyQuery() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
            #expect(body == "query=")
            return (mockResponse(), Data("[]".utf8))
        }

        let client = ShoutcastDirectoryClient(session: makeMockSession())
        let stations = try await client.search("")

        #expect(stations.isEmpty)
    }

    // MARK: - getStreamURL

    @Test func getStreamURL_returnsParsedURL() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/Player/GetStreamUrl")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
            #expect(body == "station=1552431")
            let responseJSON = Data("\"http://185.33.21.112:80/rockclassics_64a?icy=https\"".utf8)
            return (mockResponse(), responseJSON)
        }

        let client = ShoutcastDirectoryClient(session: makeMockSession())
        let url = try await client.getStreamURL(for: 1552431)

        #expect(url.absoluteString == "http://185.33.21.112:80/rockclassics_64a?icy=https")
    }

    @Test func getStreamURL_httpError() async {
        MockURLProtocol.requestHandler = { _ in
            (mockResponse(statusCode: 404), Data())
        }

        let client = ShoutcastDirectoryClient(session: makeMockSession())
        await #expect(throws: ShoutcastDirectoryError.self) {
            try await client.getStreamURL(for: 1)
        }
    }

    @Test func getStreamURL_emptyResponse() async {
        MockURLProtocol.requestHandler = { _ in
            let responseJSON = Data("\"\"".utf8)
            return (mockResponse(), responseJSON)
        }

        let client = ShoutcastDirectoryClient(session: makeMockSession())
        await #expect(throws: ShoutcastDirectoryError.self) {
            try await client.getStreamURL(for: 1)
        }
    }
}
