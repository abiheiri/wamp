import Testing
import Foundation
@testable import Wamp

@MainActor
@Suite("Track")
struct TrackTests {

    private func fixtureURL(file: StaticString = #filePath) -> URL {
        // #filePath → .../WampTests/Models/TrackTests.swift
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // WampTests/Models
            .deletingLastPathComponent()   // WampTests
            .appendingPathComponent("Fixtures/sample.m4a")
    }

    @Test func fallbackBitrate_computesFromFileSizeAndDuration() {
        // 1 MiB file over 10 seconds → 8_388_608 bits / 10 s ≈ 838 kbps.
        #expect(Track.fallbackBitrate(fileSize: 1_048_576, duration: 10) == 838)
        // Zero duration returns nil to avoid division by zero.
        #expect(Track.fallbackBitrate(fileSize: 1_048_576, duration: 0) == nil)
        // Zero file size returns nil.
        #expect(Track.fallbackBitrate(fileSize: 0, duration: 10) == nil)
    }

    @Test func fromURL_parsesMetadataTags() async {
        let track = await Track.fromURL(fixtureURL())
        #expect(track.title == "Wamp Fixture Title")
        #expect(track.artist == "Wamp Fixture Artist")
        #expect(track.album == "Wamp Fixture Album")
        #expect(track.genre == "Electronic")
    }

    @Test func fromURL_parsesAudioFormat() async {
        let track = await Track.fromURL(fixtureURL())
        #expect(track.channels == 2)
        #expect(track.sampleRate == 44_100)
        #expect(track.duration > 0.3)
        #expect(track.duration < 0.8)
    }

    @Test func fromURL_unreadableFile_fallsBackToFilename() async {
        let bogus = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).m4a")
        let track = await Track.fromURL(bogus)
        #expect(track.title == bogus.deletingPathExtension().lastPathComponent)
        #expect(track.duration == 0)
    }

    @Test func displayTitle_formatsArtistAndTitle() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/x.m4a"),
                          title: "Song", artist: "Band", album: "", duration: 0)
        #expect(track.displayTitle == "Band - Song")
    }

    @Test func displayTitle_withoutArtist_returnsTitleOnly() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/x.m4a"),
                          title: "Song", artist: "Unknown Artist", album: "", duration: 0)
        #expect(track.displayTitle == "Song")
    }

    @Test func formattedDuration_minutesAndSeconds() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/x.m4a"),
                          title: "", artist: "", album: "", duration: 125)
        #expect(track.formattedDuration == "2:05")
    }

    @Test func isCueVirtualFalseByDefault() {
        let t = Track(url: URL(fileURLWithPath: "/tmp/x.flac"),
                      title: "x", artist: "", album: "", duration: 1)
        #expect(t.cueStart == nil)
        #expect(t.cueEnd == nil)
        #expect(t.isCueVirtual == false)
    }

    @Test func isCueVirtualTrueWhenCueStartSet() {
        var t = Track(url: URL(fileURLWithPath: "/tmp/x.flac"),
                      title: "x", artist: "", album: "", duration: 30)
        t.cueStart = 10
        t.cueEnd = 40
        #expect(t.isCueVirtual == true)
    }

    @Test func codableRoundTripPreservesCueRange() throws {
        var t = Track(url: URL(fileURLWithPath: "/tmp/x.flac"),
                      title: "x", artist: "", album: "", duration: 30)
        t.cueStart = 10.5
        t.cueEnd = 40.25
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        #expect(decoded.cueStart == 10.5)
        #expect(decoded.cueEnd == 40.25)
    }

    // MARK: - shoutcastStream factory

    @Test func shoutcastStream_buildsTrackFromStation() async throws {
        let streamURL = try #require(URL(string: "http://185.33.21.112:80/stream?icy=https"))
        let station = ShoutcastStation(
            id: 1552431,
            name: "Rock Classics",
            genre: "Rock",
            bitrate: 64,
            listeners: 10,
            format: "audio/mpeg",
            streamURL: nil
        )

        let track = Track.shoutcastStream(from: station, streamURL: streamURL)

        #expect(track.url == streamURL)
        #expect(track.title == "Rock Classics")
        #expect(track.artist == "Rock Classics")
        #expect(track.album == "SHOUTcast Radio")
        #expect(track.genre == "Rock")
        #expect(track.bitrate == 64)
        #expect(track.duration == 0)
        #expect(track.channels == 2)
        #expect(track.sampleRate == 0)
    }

    @Test func shoutcastStream_formatAAC() {
        let streamURL = URL(string: "http://example.com:8000/aac")!
        let station = ShoutcastStation(
            id: 1,
            name: "AAC Station",
            genre: "Pop",
            bitrate: 128,
            listeners: 0,
            format: "audio/aac",
            streamURL: nil
        )

        let track = Track.shoutcastStream(from: station, streamURL: streamURL)

        #expect(track.url == streamURL)
        #expect(track.bitrate == 128)
    }

    @Test func shoutcastStream_noListenersStillWorks() {
        let streamURL = URL(string: "http://example.com:8000/stream")!
        let station = ShoutcastStation(
            id: 99,
            name: "Quiet FM",
            genre: "Ambient",
            bitrate: 96,
            listeners: 0,
            format: "audio/mpeg",
            streamURL: nil
        )

        let track = Track.shoutcastStream(from: station, streamURL: streamURL)

        #expect(track.title == "Quiet FM")
        #expect(track.duration == 0)
    }
}
