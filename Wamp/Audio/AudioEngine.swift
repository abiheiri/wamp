import Foundation
import AVFoundation
import Combine
import Accelerate

enum RepeatMode: Int, Codable {
    case off = 0
    case track = 1
    case playlist = 2
}

enum PlayState {
    case stopped
    case playing
    case paused
}

extension Notification.Name {
    static let trackDidFinish = Notification.Name("trackDidFinish")
}

extension AudioEngine {
    /// userInfo key on `.trackDidFinish`: true when the engine has already
    /// promoted a queued gapless segment and audio is continuing seamlessly —
    /// the playlist should only advance its index, not start playback anew.
    static let gaplessChainedKey = "gaplessChained"
}

class AudioEngine: ObservableObject {
    // MARK: - Published State
    @Published var isPlaying = false
    @Published var playState: PlayState = .stopped
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 0.75 {
        didSet { engine.mainMixerNode.outputVolume = effectiveVolume }
    }
    @Published var balance: Float = 0 {
        didSet { playerNode.pan = balance }
    }
    @Published var isMuted = false {
        didSet { engine.mainMixerNode.outputVolume = effectiveVolume }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published var eqEnabled = true {
        didSet { eq.bypass = !eqEnabled }
    }
    @Published var preampGain: Float = 0 // dB, -12 to +12
    @Published var spectrumData: [Float] = Array(repeating: 0, count: 32)

    // MARK: - EQ State
    @Published private(set) var eqBands: [Float] = Array(repeating: 0, count: 10) // dB per band

    static let eqFrequencies: [Float] = [
        70, 180, 320, 600, 1000, 3000, 6000, 12000, 14000, 16000
    ]

    // MARK: - Private
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq: AVAudioUnitEQ
    private var audioFile: AVAudioFile?
    private var seekFrame: AVAudioFramePosition = 0
    private var audioSampleRate: Double = 44100
    private var audioLengthFrames: AVAudioFramePosition = 0
    private var timeUpdateTimer: Timer?
    private var needsScheduling = true
    private var playbackGeneration: UInt64 = 0
    /// Upper frame bound of the segment currently scheduled. Matches
    /// `audioLengthFrames` for a whole-file play, or the CUE track's end frame
    /// when we're playing a bounded segment.
    private var currentSegmentEndFrame: AVAudioFramePosition = 0
    /// Logical start frame of the current track's segment (0 for whole-file
    /// playback, the CUE start frame for virtual tracks). Unlike `seekFrame`
    /// it is not moved by seeks — repeat-one loops back to it.
    private var currentSegmentStartFrame: AVAudioFramePosition = 0
    /// Set by `chainNextSegment` when a follow-up segment has already been
    /// queued on the player node. Consumed by `handleTrackCompletion` so the
    /// engine keeps playing into the chained segment without re-loading.
    private var pendingChain: (startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition)?

    // MARK: - Streaming State

    private var streamParser: ShoutcastStreamParser?
    private var streamConverter: AVAudioConverter?
    private var streamSourceNode: AVAudioPlayerNode?
    private var streamOutputFormat: AVAudioFormat?
    private var isStreaming = false

    private var effectiveVolume: Float {
        // Preamp is folded in so volume/mute changes don't silently wipe it.
        (isMuted ? 0 : volume) * pow(10, preampGain / 20)
    }

    // MARK: - Init
    init() {
        eq = AVAudioUnitEQ(numberOfBands: 10)
        setupAudioChain()
        setupEQBands()
    }

    private func setupAudioChain() {
        engine.attach(playerNode)
        engine.attach(eq)
        engine.connect(playerNode, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = effectiveVolume
    }

    private func setupEQBands() {
        for (i, freq) in Self.eqFrequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
    }

    // MARK: - Playback Controls

    /// Loads an audio file and prepares duration/metadata without starting playback.
    func load(url: URL) {
        stop()
        playbackGeneration &+= 1

        do {
            try loadFile(url: url)
        } catch {
            print("🔴 AudioEngine: failed to load \(url.lastPathComponent): \(error)")
        }
    }

    func loadAndPlay(url: URL) {
        print("🔵 loadAndPlay: \(url.lastPathComponent), gen=\(playbackGeneration)")
        stop()
        playbackGeneration &+= 1
        print("🔵 loadAndPlay: after stop, new gen=\(playbackGeneration)")

        do {
            try loadFile(url: url)

            if !engine.isRunning {
                try engine.start()
                print("🔵 loadAndPlay: engine started")
            }
            installSpectrumTap()
            scheduleAndPlay()
        } catch {
            print("🔴 AudioEngine: failed to load \(url.lastPathComponent): \(error)")
        }
    }

    /// Schedule a follow-up segment back-to-back on the same player node —
    /// no `stop()`, no reload — so the boundary is sample-exact. Returns true
    /// on success, false if the engine isn't currently playing this file.
    ///
    /// The chained segment's completion handler fires `.trackDidFinish` when
    /// the chained segment itself ends. When the *prior* segment ends its
    /// completion handler will also fire; it consumes `pendingChain` and
    /// updates the seek/end bookkeeping without interrupting playback.
    @discardableResult
    func chainNextSegment(url: URL, startTime: TimeInterval, endTime: TimeInterval?) -> Bool {
        guard isPlaying, let file = audioFile, file.url == url else { return false }
        let startFrame = AVAudioFramePosition(startTime * audioSampleRate)
        let endFrame: AVAudioFramePosition
        if let endTime = endTime {
            endFrame = min(audioLengthFrames, AVAudioFramePosition(endTime * audioSampleRate))
        } else {
            endFrame = audioLengthFrames
        }
        let frames = endFrame - startFrame
        guard frames > 0 else { return false }

        let generation = playbackGeneration
        playerNode.scheduleSegment(
            file,
            startingFrame: max(0, startFrame),
            frameCount: AVAudioFrameCount(frames),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == generation else { return }
                self.handleTrackCompletion()
            }
        }
        pendingChain = (startFrame: max(0, startFrame), endFrame: endFrame)
        return true
    }

    /// Load `url` and play from `startTime` until `endTime` (or EOF if nil).
    /// Used for CUE-derived virtual tracks. When playback reaches the end frame
    /// the completion handler posts `.trackDidFinish` exactly like a normal track.
    func loadAndPlay(url: URL, startTime: TimeInterval, endTime: TimeInterval?) {
        print("🔵 loadAndPlay(range): \(url.lastPathComponent) [\(startTime), \(endTime as Any)]")
        stop()
        playbackGeneration &+= 1

        do {
            try loadFile(url: url)
            if !engine.isRunning { try engine.start() }
            installSpectrumTap()

            let startFrame = AVAudioFramePosition(startTime * audioSampleRate)
            let endFrame: AVAudioFramePosition
            if let endTime = endTime {
                endFrame = min(audioLengthFrames, AVAudioFramePosition(endTime * audioSampleRate))
            } else {
                endFrame = audioLengthFrames
            }
            seekFrame = max(0, min(startFrame, audioLengthFrames))
            currentSegmentStartFrame = seekFrame
            scheduleSegment(endFrame: endFrame)
        } catch {
            print("🔴 AudioEngine: failed to load \(url.lastPathComponent): \(error)")
        }
    }

    /// Shared helper: opens the audio file and sets duration/sample-rate metadata.
    private func loadFile(url: URL) throws {
        audioFile = try AVAudioFile(forReading: url)
        guard let file = audioFile else {
            print("🔴 loadFile: audioFile is nil after init")
            return
        }

        audioSampleRate = file.processingFormat.sampleRate
        audioLengthFrames = file.length
        duration = Double(audioLengthFrames) / audioSampleRate
        seekFrame = 0
        needsScheduling = true
        currentSegmentStartFrame = 0
        currentSegmentEndFrame = 0
        print("🔵 loadFile: file loaded, sampleRate=\(audioSampleRate), frames=\(audioLengthFrames), duration=\(duration)s")
    }

    func play() {
        guard audioFile != nil else { return }
        do {
            if !engine.isRunning {
                try engine.start()
            }
            installSpectrumTap()
            if needsScheduling {
                // Respect the active CUE segment bound (set by a paused seek);
                // scheduling to EOF here would bleed past the cue track's end.
                scheduleSegment(endFrame: currentSegmentEndFrame > 0 ? currentSegmentEndFrame : audioLengthFrames)
            } else {
                playerNode.play()
            }
            isPlaying = true
            playState = .playing
            startTimeUpdates()
        } catch {
            print("AudioEngine: failed to start: \(error)")
        }
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        playState = .paused
        stopTimeUpdates()
    }

    func stop() {
        print("🟡 stop() called, gen=\(playbackGeneration), isPlaying=\(isPlaying)")
        playerNode.stop()
        isPlaying = false
        playState = .stopped
        currentTime = 0
        seekFrame = 0
        needsScheduling = true
        pendingChain = nil
        currentSegmentStartFrame = 0
        currentSegmentEndFrame = 0
        stopTimeUpdates()
        stopStream()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval) {
        guard audioFile != nil else { return }
        let targetFrame = AVAudioFramePosition(time * audioSampleRate)
        let upperBound = currentSegmentEndFrame > 0 ? currentSegmentEndFrame : audioLengthFrames
        seekFrame = max(0, min(targetFrame, upperBound))
        needsScheduling = true
        // Rescheduling wipes the player node's queue, so any chained gapless
        // segment is gone — forget it, or completion bookkeeping derails.
        pendingChain = nil

        if isPlaying {
            scheduleSegment(endFrame: upperBound)
        } else {
            currentTime = time
        }
    }

    // MARK: - Streaming

    /// Begin streaming audio from a SHOUTcast/ICEcast URL.
    /// Routes audio through the full DSP chain (EQ → mixer → output).
    func playStream(url streamURL: URL) {
        stop()
        stopStream()
        isStreaming = true

        // Create and attach a dedicated node for streaming
        let streamNode = AVAudioPlayerNode()
        engine.attach(streamNode)
        engine.connect(streamNode, to: eq, format: nil)
        streamSourceNode = streamNode

        streamOutputFormat = AVAudioFormat(
            standardFormatWithSampleRate: 44100,
            channels: 2
        )

        // Start the engine if not running
        if !engine.isRunning {
            do { try engine.start() } catch {
                print("🔴 AudioEngine: failed to start engine for stream: \(error)")
                return
            }
        }
        installSpectrumTap()

        // Set up parser
        let parser = ShoutcastStreamParser()
        streamParser = parser

        parser.onFormatReady = { [weak self] format in
            guard let self, self.isStreaming else { return }
            guard let outputFormat = self.streamOutputFormat else { return }

            let converter = AVAudioConverter(from: format, to: outputFormat)
            self.streamConverter = converter
        }

        parser.onPackets = { [weak self] packets in
            guard let self, self.isStreaming,
                  let converter = self.streamConverter,
                  let outputFormat = self.streamOutputFormat,
                  let streamNode = self.streamSourceNode else { return }

            for packet in packets {
                let packetSize = packet.data.count

                // Create compressed input buffer and copy audio data into its mData area.
                let inputBuffer = AVAudioCompressedBuffer(
                    format: converter.inputFormat,
                    packetCapacity: 1,
                    maximumPacketSize: packetSize
                )

                let bufferList = UnsafeMutableAudioBufferListPointer(
                    inputBuffer.data.assumingMemoryBound(to: AudioBufferList.self)
                )
                guard bufferList.count > 0 else { continue }
                var audioBuffer = bufferList[0]
                guard let mData = audioBuffer.mData else { continue }

                (packet.data as NSData).getBytes(mData, length: packetSize)
                audioBuffer.mDataByteSize = UInt32(packetSize)
                inputBuffer.packetCount = 1
                if let desc = packet.packetDescription {
                    inputBuffer.packetDescriptions?.pointee = desc
                }

                // Convert to PCM
                let frameCapacity: AVAudioFrameCount = 1152 // MP3 frame default
                guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: frameCapacity
                ) else { continue }

                // Provide the single input packet exactly once.
                var packetProvided = false

                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) { _, status in
                    if !packetProvided {
                        packetProvided = true
                        status.pointee = .haveData
                        return inputBuffer
                    } else {
                        status.pointee = .noDataNow
                        return nil
                    }
                }

                if status == .error || conversionError != nil {
                    continue
                }

                // Schedule into the player node
                streamNode.scheduleBuffer(outputBuffer, completionHandler: nil)

                // Start the node on first buffer
                if !streamNode.isPlaying {
                    streamNode.play()
                    DispatchQueue.main.async { [weak self] in
                        self?.isPlaying = true
                        self?.playState = .playing
                        self?.duration = 0 // live stream — no fixed duration
                    }
                }
            }
        }

        parser.onMetadata = { [weak self] metadata in
            guard self?.isStreaming == true else { return }
            if !metadata.streamTitle.isEmpty {
                print("🎵 Now Playing: \(metadata.streamTitle)")
            }
        }

        parser.onError = { [weak self] error in
            print("🔴 AudioEngine: stream error: \(error)")
            DispatchQueue.main.async {
                self?.handleStreamError()
            }
        }

        currentTime = 0
        duration = 0
        parser.start(url: streamURL)
    }

    /// Stop the active stream and clean up streaming resources.
    func stopStream() {
        isStreaming = false
        streamParser?.stop()
        streamParser = nil
        streamConverter = nil

        if let node = streamSourceNode {
            node.stop()
            engine.detach(node)
            streamSourceNode = nil
        }
        streamOutputFormat = nil
    }

    private func handleStreamError() {
        guard isStreaming else { return }
        isPlaying = false
        playState = .stopped
        stopStream()
    }

    // MARK: - EQ
    func setEQ(band: Int, gain: Float) {
        guard band >= 0, band < 10 else { return }
        let clampedGain = max(-12, min(12, gain))
        eqBands[band] = clampedGain
        eq.bands[band].gain = clampedGain
    }

    func setPreamp(gain: Float) {
        preampGain = max(-12, min(12, gain))
        engine.mainMixerNode.outputVolume = effectiveVolume
    }

    func setAllEQBands(_ gains: [Float]) {
        for (i, gain) in gains.prefix(10).enumerated() {
            setEQ(band: i, gain: gain)
        }
    }

    func resetEQ() {
        setAllEQBands(Array(repeating: 0, count: 10))
        setPreamp(gain: 0)
    }

    // MARK: - Private Playback
    private func scheduleAndPlay() {
        scheduleSegment(endFrame: audioLengthFrames)
    }

    private func scheduleSegment(endFrame: AVAudioFramePosition) {
        guard let file = audioFile else {
            print("🔴 scheduleSegment: no audioFile")
            return
        }
        let framesToPlay = endFrame - seekFrame
        print("🟢 scheduleSegment: framesToPlay=\(framesToPlay), seekFrame=\(seekFrame), endFrame=\(endFrame), gen=\(playbackGeneration)")
        guard framesToPlay > 0 else {
            print("🔴 scheduleSegment: no frames to play, calling handleTrackCompletion")
            handleTrackCompletion()
            return
        }

        // Invalidate completion handlers of whatever was scheduled before:
        // playerNode.stop() fires them asynchronously, and without the bump
        // they'd be mistaken for a genuine end-of-segment.
        playbackGeneration &+= 1
        playerNode.stop()
        let generation = playbackGeneration
        let capturedEnd = endFrame
        playerNode.scheduleSegment(
            file,
            startingFrame: seekFrame,
            frameCount: AVAudioFrameCount(framesToPlay),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == generation else { return }
                self.handleTrackCompletion()
            }
        }
        playerNode.play()
        isPlaying = true
        playState = .playing
        needsScheduling = false
        currentSegmentEndFrame = capturedEnd
        startTimeUpdates()
    }

    private func handleTrackCompletion() {
        print("🔴 handleTrackCompletion: isPlaying=\(isPlaying), repeatMode=\(repeatMode), gen=\(playbackGeneration)")
        guard isPlaying else {
            print("🔴 handleTrackCompletion: NOT playing, ignoring")
            return
        }

        if repeatMode == .track {
            // Loop the current track's segment, not the whole file — for a CUE
            // virtual track that segment is a slice of the album file.
            pendingChain = nil
            seekFrame = currentSegmentStartFrame
            needsScheduling = true
            scheduleSegment(endFrame: currentSegmentEndFrame > 0 ? currentSegmentEndFrame : audioLengthFrames)
            return
        }

        // Gapless chain: the next segment is already queued on the player node
        // and may already be feeding audio. Adopt its bookkeeping and notify
        // the playlist, but do NOT stop or reset the engine.
        if let pending = pendingChain {
            // playerTime.sampleTime keeps counting across the chain boundary
            // (no node stop), so rebase seekFrame by the just-finished
            // segment's length — otherwise currentTime overcounts by it.
            let finishedLength = max(0, currentSegmentEndFrame - seekFrame)
            seekFrame = pending.startFrame - finishedLength
            currentSegmentStartFrame = pending.startFrame
            currentSegmentEndFrame = pending.endFrame
            pendingChain = nil
            print("🟢 handleTrackCompletion: promoted chained segment [\(pending.startFrame), \(pending.endFrame)]")
            NotificationCenter.default.post(name: .trackDidFinish, object: nil,
                                            userInfo: [AudioEngine.gaplessChainedKey: true])
            return
        }

        isPlaying = false
        playState = .stopped
        stopTimeUpdates()
        print("🔴 handleTrackCompletion: posting .trackDidFinish")
        NotificationCenter.default.post(name: .trackDidFinish, object: nil)
    }

    // MARK: - Time Updates
    private func startTimeUpdates() {
        stopTimeUpdates()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
        }
    }

    private func stopTimeUpdates() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }

    private func updateCurrentTime() {
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        currentTime = Double(seekFrame + playerTime.sampleTime) / audioSampleRate
    }

    // MARK: - Spectrum Tap
    private func installSpectrumTap() {
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        mixer.removeTap(onBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processSpectrumData(buffer: buffer)
        }
    }

    private func processSpectrumData(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Use power-of-2 size for FFT
        let log2n = vDSP_Length(log2(Float(frameCount)))
        let fftSize = Int(1 << log2n)
        let halfSize = fftSize / 2
        // The tap doesn't guarantee buffer sizes; with halfSize below the
        // 32-bin output the mapping loop would form an empty range and trap.
        guard halfSize >= 32 else { return }

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Apply Hann window
        var windowed = [Float](repeating: 0, count: fftSize)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(channelData, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // Split complex for FFT
        var realPart = [Float](repeating: 0, count: halfSize)
        var imagPart = [Float](repeating: 0, count: halfSize)
        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                windowed.withUnsafeBytes { rawBuf in
                    let complexPtr = rawBuf.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(complexPtr.baseAddress!, 2, &splitComplex, 1, vDSP_Length(halfSize))
                }
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Compute magnitudes
                var magnitudes = [Float](repeating: 0, count: halfSize)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))

                // Scale and map to 32 bins
                let binCount = 32
                var spectrum = [Float](repeating: 0, count: binCount)
                let binsPerOutput = max(1, halfSize / binCount)

                for i in 0..<binCount {
                    let start = i * binsPerOutput
                    let end = min(start + binsPerOutput, halfSize)
                    var sum: Float = 0
                    vDSP_sve(Array(magnitudes[start..<end]), 1, &sum, vDSP_Length(end - start))
                    spectrum[i] = sqrt(sum / Float(end - start)) * 0.05
                }

                DispatchQueue.main.async { [weak self] in
                    self?.spectrumData = spectrum
                }
            }
        }
    }

    deinit {
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
    }
}
