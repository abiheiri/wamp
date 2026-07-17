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

private func mockResponse(url: URL, statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

private let mirrorA = URL(string: "https://a.api.example")!
private let mirrorB = URL(string: "https://b.api.example")!

private func makeClient(mirrors: [URL] = [mirrorA]) -> RadioBrowserClient {
    RadioBrowserClient(session: makeMockSession(), mirrors: mirrors)
}

private let validStationJSON = """
[
    {
        "stationuuid": "9617a958-0601-11e8-ae97-52543be04c81",
        "name": "SomaFM Groove Salad ",
        "url": "http://somafm.com/groovesalad.pls",
        "url_resolved": "https://ice2.somafm.com/groovesalad-128-mp3",
        "tags": "ambient,chillout",
        "codec": "MP3",
        "bitrate": 128,
        "clickcount": 4200,
        "votes": 900,
        "lastcheckok": 1
    },
    {
        "stationuuid": "78012206-1aa1-11e9-a80b-52543be04c81",
        "name": "Radio Paradise",
        "url": "https://stream.radioparadise.com/aac-320",
        "url_resolved": "",
        "tags": "eclectic",
        "codec": "AAC",
        "bitrate": 320,
        "clickcount": 9000,
        "votes": 2000,
        "lastcheckok": 1
    }
]
""".data(using: .utf8)!

// MARK: - Tests

@MainActor
@Suite("RadioBrowserClient", .serialized)
struct RadioBrowserClientTests {

    // MARK: - stationsByTag

    @Test func stationsByTag_parsesAndMapsStations() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            #expect(url.path == "/json/stations/bytagexact/rock")
            let query = url.query ?? ""
            #expect(query.contains("hidebroken=true"))
            #expect(query.contains("order=clickcount"))
            #expect(query.contains("reverse=true"))
            return (mockResponse(url: url), validStationJSON)
        }

        let stations = try await makeClient().stationsByTag("rock")

        #expect(stations.count == 2)
        #expect(stations[0].id == "9617a958-0601-11e8-ae97-52543be04c81")
        #expect(stations[0].source == .radioBrowser)
        #expect(stations[0].name == "SomaFM Groove Salad")
        #expect(stations[0].genre == "ambient,chillout")
        #expect(stations[0].bitrate == 128)
        #expect(stations[0].popularity == 4200)
        #expect(stations[0].format == "MP3")
        #expect(stations[0].streamURL?.absoluteString == "https://ice2.somafm.com/groovesalad-128-mp3")
    }

    @Test func stationsByTag_lowercasesTag() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/json/stations/bytagexact/rock")
            return (mockResponse(url: request.url!), Data("[]".utf8))
        }
        _ = try await makeClient().stationsByTag("Rock")
    }

    @Test func emptyResolvedURL_fallsBackToRawURL() async throws {
        MockURLProtocol.requestHandler = { request in
            (mockResponse(url: request.url!), validStationJSON)
        }
        let stations = try await makeClient().stationsByTag("rock")
        #expect(stations[1].streamURL?.absoluteString == "https://stream.radioparadise.com/aac-320")
    }

    @Test func unplayableStations_areDropped() async throws {
        let json = """
        [
            {"stationuuid": "u1", "name": "No URL", "url": "", "url_resolved": "",
             "tags": "", "codec": "MP3", "bitrate": 128, "clickcount": 1, "votes": 0, "lastcheckok": 1},
            {"stationuuid": "u2", "name": "  ", "url": "http://x.example/s", "url_resolved": "",
             "tags": "", "codec": "MP3", "bitrate": 128, "clickcount": 1, "votes": 0, "lastcheckok": 1},
            {"stationuuid": "u3", "name": "Good", "url": "http://x.example/g", "url_resolved": "",
             "tags": "", "codec": "MP3", "bitrate": 128, "clickcount": 1, "votes": 0, "lastcheckok": 1}
        ]
        """
        MockURLProtocol.requestHandler = { request in
            (mockResponse(url: request.url!), Data(json.utf8))
        }
        let stations = try await makeClient().stationsByTag("rock")
        #expect(stations.map(\.name) == ["Good"])
    }

    @Test func sendsWampUserAgent() async throws {
        MockURLProtocol.requestHandler = { request in
            let ua = request.value(forHTTPHeaderField: "User-Agent") ?? ""
            #expect(ua.hasPrefix("Wamp/"))
            return (mockResponse(url: request.url!), Data("[]".utf8))
        }
        _ = try await makeClient().stationsByTag("rock")
    }

    // MARK: - searchStations

    @Test func search_hitsSearchEndpointWithName() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            #expect(url.path == "/json/stations/search")
            let query = url.query ?? ""
            #expect(query.contains("name=jazz"))
            #expect(query.contains("hidebroken=true"))
            return (mockResponse(url: url), validStationJSON)
        }
        let stations = try await makeClient().searchStations("jazz")
        #expect(stations.count == 2)
    }

    // MARK: - fetchTopTags

    @Test func fetchTopTags_parsesTags() async throws {
        let json = """
        [
            {"name": "pop", "stationcount": 9000},
            {"name": "rock", "stationcount": 8500},
            {"name": "synthwave", "stationcount": 300}
        ]
        """
        MockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            #expect(url.path == "/json/tags")
            let query = url.query ?? ""
            #expect(query.contains("order=stationcount"))
            #expect(query.contains("reverse=true"))
            #expect(query.contains("limit=100"))
            return (mockResponse(url: url), Data(json.utf8))
        }
        let tags = try await makeClient().fetchTopTags(limit: 100)
        #expect(tags.count == 3)
        #expect(tags[0] == RadioBrowserTag(name: "pop", stationcount: 9000))
        #expect(tags[2].name == "synthwave")
    }

    // MARK: - Mirror failover

    @Test func failover_secondMirrorServesAfterFirstFails() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            if url.host == mirrorA.host {
                return (mockResponse(url: url, statusCode: 503), Data())
            }
            return (mockResponse(url: url), validStationJSON)
        }
        let stations = try await makeClient(mirrors: [mirrorA, mirrorB]).stationsByTag("rock")
        #expect(stations.count == 2)
    }

    @Test func allMirrorsFail_throws() async {
        MockURLProtocol.requestHandler = { request in
            (mockResponse(url: request.url!, statusCode: 500), Data())
        }
        await #expect(throws: RadioBrowserError.self) {
            _ = try await makeClient(mirrors: [mirrorA, mirrorB]).stationsByTag("rock")
        }
    }

    // MARK: - Click ping

    @Test func registerClick_hitsURLEndpoint_andNeverThrows() async {
        nonisolated(unsafe) var requestedPath: String?
        MockURLProtocol.requestHandler = { request in
            requestedPath = request.url?.path
            return (mockResponse(url: request.url!, statusCode: 500), Data())
        }
        await makeClient().registerClick(stationUUID: "9617a958")
        #expect(requestedPath == "/json/url/9617a958")
    }
}
