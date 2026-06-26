import Foundation
import AVFoundation
import AudioToolbox

// MARK: - Packet

/// A parsed audio packet from the MP3/AAC stream, ready for conversion to PCM.
struct ShoutcastAudioPacket {
    let data: Data
    let packetDescription: AudioStreamPacketDescription?
}

// MARK: - Error

enum ShoutcastStreamError: Error {
    case invalidResponse
    case audioFileStreamInit(OSStatus)
    case audioFileStreamParse(OSStatus)
}

// MARK: - Parser

/// Manages an HTTP streaming connection to a SHOUTcast/ICEcast server,
/// strips ICY metadata, and parses the MP3/AAC stream via AudioFileStream.
final class ShoutcastStreamParser: NSObject, URLSessionDataDelegate {

    // MARK: - Callbacks

    /// Called when ICY metadata (track title, etc.) is received.
    var onMetadata: ((ICYMetadata) -> Void)?

    /// Called when AudioFileStream discovers the audio format.
    var onFormatReady: ((AVAudioFormat) -> Void)?

    /// Called for each batch of parsed audio packets.
    var onPackets: (([ShoutcastAudioPacket]) -> Void)?

    /// Called when a stream error occurs.
    var onError: ((Error) -> Void)?

    // MARK: - Public

    var isRunning: Bool { dataTask != nil }

    /// Start streaming from a URL. ICY metadata interval is auto-discovered from HTTP headers.
    func start(url: URL) {
        stop()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 86400 // long-lived stream
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        var request = URLRequest(url: url)
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.timeoutInterval = 30

        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
    }

    /// Stop the stream and tear down all state.
    func stop() {
        dataTask?.cancel()
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil

        if let streamID = audioFileStreamID {
            AudioFileStreamClose(streamID)
            audioFileStreamID = nil
        }
        audioFileStreamID = nil

        icyInterval = 0
        bytesUntilMetadata = 0
        buffer = Data()
    }

    // MARK: - Private State

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var audioFileStreamID: AudioFileStreamID?

    private var icyInterval = 0
    private var bytesUntilMetadata = 0
    private var buffer = Data()

    // We must hold a strong reference to self while parsing to keep AudioFileStream callbacks alive.
    // The URLSession delegate retains self via the session, but the AudioFileStream callbacks use
    // an unretained pointer. The session already keeps self alive.
}

// MARK: - URLSessionDataDelegate

extension ShoutcastStreamParser {

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async {
        // Extract ICY metadata interval from HTTP headers
        if let httpResponse = response as? HTTPURLResponse {
            let headers = httpResponse.allHeaderFields as? [String: String] ?? [:]
            let interval = ICYMetadataParser.metadataInterval(from: headers)
            if interval > 0 {
                icyInterval = interval
                bytesUntilMetadata = interval
            }
        }

        // AudioFileStream needs to know the type hint (MP3 vs AAC).
        // SHOUTcast streams are always MP3 or AAC (from the station format).
        let mimeType = response.mimeType ?? "audio/mpeg"
        let hint: AudioFileTypeID = mimeType.contains("aac") ? kAudioFileAAC_ADTSType : kAudioFileMP3Type

        var streamID: AudioFileStreamID?
        let status = AudioFileStreamOpen(
            Unmanaged.passUnretained(self).toOpaque(),
            propertyListenerCallback,
            packetCallback,
            hint,
            &streamID
        )

        guard status == noErr, let streamID = streamID else {
            onError?(ShoutcastStreamError.audioFileStreamInit(status))
            return
        }
        audioFileStreamID = streamID
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let streamID = audioFileStreamID else {
            // Buffer until we have the stream parser ready
            buffer.append(data)
            return
        }

        // Feed any buffered data first
        if !buffer.isEmpty {
            let buffered = buffer
            buffer = Data()
            processIncomingAudio(buffered, streamID: streamID)
        }

        processIncomingAudio(data, streamID: streamID)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onError?(error)
        }
    }

    // MARK: - Audio Stream Processing

    /// Strip ICY metadata from incoming bytes and feed audio data to AudioFileStream.
    private func processIncomingAudio(_ data: Data, streamID: AudioFileStreamID) {
        guard icyInterval > 0 else {
            // No metadata — feed directly
            parseAudioData(data, streamID: streamID)
            return
        }

        var offset = 0
        while offset < data.count {
            if bytesUntilMetadata == 0 {
                // Read metadata length byte
                let metaLength = Int(data[offset]) * 16
                offset += 1

                if metaLength > 0 {
                    let metaEnd = min(offset + metaLength, data.count)
                    let metaData = data.subdata(in: offset..<metaEnd)
                    if let metadata = ICYMetadataParser.parse(metaData) {
                        DispatchQueue.main.async { [weak self] in
                            self?.onMetadata?(metadata)
                        }
                    }
                    offset = metaEnd
                }

                // Reset counter for next audio block
                bytesUntilMetadata = icyInterval
            } else {
                // Feed audio bytes up to the next metadata boundary
                let audioBytesRemaining = min(bytesUntilMetadata, data.count - offset)
                let audioEnd = offset + audioBytesRemaining
                let audioChunk = data.subdata(in: offset..<audioEnd)
                parseAudioData(audioChunk, streamID: streamID)

                bytesUntilMetadata -= audioBytesRemaining
                offset = audioEnd
            }
        }
    }

    private func parseAudioData(_ data: Data, streamID: AudioFileStreamID) {
        let status = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            AudioFileStreamParseBytes(streamID, UInt32(data.count), ptr.baseAddress!, [])
        }
        if status != noErr {
            onError?(ShoutcastStreamError.audioFileStreamParse(status))
        }
    }
}

// MARK: - AudioFileStream Callbacks

private nonisolated func propertyListenerCallback(
    _ context: UnsafeMutableRawPointer,
    _ streamID: AudioFileStreamID,
    _ propertyID: AudioFileStreamPropertyID,
    _ flags: UnsafeMutablePointer<AudioFileStreamPropertyFlags>
) {
    let parser = Unmanaged<ShoutcastStreamParser>.fromOpaque(context).takeUnretainedValue()

    if propertyID == kAudioFileStreamProperty_DataFormat {
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        AudioFileStreamGetProperty(streamID, propertyID, &size, &asbd)

        let format = AVAudioFormat(streamDescription: &asbd)
        if let format {
            DispatchQueue.main.async {
                parser.onFormatReady?(format)
            }
        }
    }
}

private nonisolated func packetCallback(
    _ context: UnsafeMutableRawPointer,
    _ numberBytes: UInt32,
    _ numberPackets: UInt32,
    _ inputData: UnsafeRawPointer,
    _ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
) {
    let parser = Unmanaged<ShoutcastStreamParser>.fromOpaque(context).takeUnretainedValue()

    guard numberPackets > 0 else { return }

    var packets: [ShoutcastAudioPacket] = []
    packets.reserveCapacity(Int(numberPackets))

    if let descriptions = packetDescriptions {
        // VBR: each packet has a size + offset description
        for i in 0..<Int(numberPackets) {
            let desc = descriptions[i]
            let packetData = Data(bytes: inputData.advanced(by: Int(desc.mStartOffset)), count: Int(desc.mDataByteSize))
            packets.append(ShoutcastAudioPacket(data: packetData, packetDescription: desc))
        }
    } else {
        // CBR: all packets are the same size
        let bytesPerPacket = Int(numberBytes) / Int(numberPackets)
        for i in 0..<Int(numberPackets) {
            let offset = i * bytesPerPacket
            let packetData = Data(bytes: inputData.advanced(by: offset), count: bytesPerPacket)
            packets.append(ShoutcastAudioPacket(data: packetData, packetDescription: nil))
        }
    }

    DispatchQueue.main.async {
        parser.onPackets?(packets)
    }
}
