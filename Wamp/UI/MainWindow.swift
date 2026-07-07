import Cocoa
import Combine
import QuartzCore

class MainWindow: NSWindow {
    let mainPlayerView = MainPlayerView()
    let equalizerView = EqualizerView()
    let playlistView = PlaylistView()
    private var cancellables = Set<AnyCancellable>()
    private weak var audioEngine: AudioEngine?

    var showEqualizer: Bool = true {
        didSet {
            mainPlayerView.isEQActive = showEqualizer
            updateSectionVisibility()
            recalculateSize()
        }
    }

    var showPlaylist: Bool = true {
        didSet {
            mainPlayerView.isPLActive = showPlaylist
            updateSectionVisibility()
            recalculateSize()
        }
    }

    /// Windowshade: collapse the whole window to just the title-bar strip,
    /// hiding the player body, EQ, and playlist. The EQ/playlist *intent*
    /// (showEqualizer/showPlaylist) is preserved and restored on un-shade.
    var windowShade: Bool = false {
        didSet {
            guard windowShade != oldValue else { return }
            mainPlayerView.isWindowShade = windowShade
            updateSectionVisibility()
            recalculateSize()
        }
    }

    private func updateSectionVisibility() {
        equalizerView.isHidden = windowShade || !showEqualizer
        playlistView.isHidden = windowShade || !showPlaylist
    }

    func toggleWindowShade() { windowShade.toggle() }

    var alwaysOnTop: Bool = false {
        didSet {
            level = alwaysOnTop ? .floating : .normal
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        let height = mainPlayerView.desiredHeight + equalizerView.desiredHeight + WinampTheme.playlistMinHeight
        let s = WinampTheme.scale
        // Round to integer points so all layout math lands on whole-pixel boundaries.
        let scaledWidth = (WinampTheme.windowWidth * s).rounded()
        let scaledHeight = (height * s).rounded()
        let rect = NSRect(x: 100, y: 100, width: scaledWidth, height: scaledHeight)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        isMovableByWindowBackground = false
        level = .normal
        backgroundColor = WinampTheme.frameBackground
        isOpaque = true
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
        container.setBoundsSize(NSSize(width: WinampTheme.windowWidth, height: height))
        container.wantsLayer = true
        contentView = container

        container.addSubview(mainPlayerView)
        container.addSubview(equalizerView)
        container.addSubview(playlistView)

        layoutSections()
    }

    private func layoutSections() {
        let w = WinampTheme.windowWidth
        let totalHeight = contentView?.bounds.height ?? frame.height
        var y = totalHeight

        // Main player — always at top
        let mainH = mainPlayerView.desiredHeight
        y -= mainH
        mainPlayerView.frame = NSRect(x: 0, y: y, width: w, height: mainH)

        // Equalizer — below player
        if showEqualizer && !windowShade {
            let eqH = equalizerView.desiredHeight
            y -= eqH
            equalizerView.frame = NSRect(x: 0, y: y, width: w, height: eqH)
        }

        // Playlist — fills remaining space
        if showPlaylist && !windowShade {
            let playlistHeight = y
            playlistView.frame = NSRect(x: 0, y: 0, width: w, height: playlistHeight)
        }
    }

    func recalculateSize() {
        var height: CGFloat = mainPlayerView.desiredHeight
        if !windowShade {
            if showEqualizer { height += equalizerView.desiredHeight }
            if showPlaylist { height += WinampTheme.playlistMinHeight }
        }

        let s = WinampTheme.scale
        let scaledWidth = (WinampTheme.windowWidth * s).rounded()
        let scaledHeight = (height * s).rounded()

        let origin = frame.origin
        let newFrame = NSRect(
            x: origin.x,
            y: origin.y + frame.height - scaledHeight,
            width: scaledWidth,
            height: scaledHeight
        )
        setFrame(newFrame, display: true, animate: true)

        contentView?.frame = NSRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)
        contentView?.setBoundsSize(NSSize(width: WinampTheme.windowWidth, height: height))
        layoutSections()
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            NSApp.sendAction(#selector(AppDelegate.togglePlayPause), to: nil, from: self)
            return
        }
        if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            let seekStep: TimeInterval = 5
            switch event.keyCode {
            case 123: // left arrow
                if let engine = audioEngine {
                    engine.seek(to: max(0, engine.currentTime - seekStep))
                }
                return
            case 124: // right arrow
                if let engine = audioEngine {
                    engine.seek(to: min(engine.duration, engine.currentTime + seekStep))
                }
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    func bindToModels(audioEngine: AudioEngine, playlistManager: PlaylistManager, radioManager: RadioManager) {
        self.audioEngine = audioEngine
        mainPlayerView.bindToModels(audioEngine: audioEngine, playlistManager: playlistManager, radioManager: radioManager)
        equalizerView.bindToModel(audioEngine: audioEngine, playlistManager: playlistManager)
        playlistView.bindToModel(playlistManager: playlistManager, radioManager: radioManager)

        // Close glyphs in the classic chrome hide the section, mirroring the
        // EQ / PL toggle buttons on the main window.
        equalizerView.onClose = { [weak self] in self?.showEqualizer = false }
        playlistView.onCloseWindow = { [weak self] in self?.showPlaylist = false }

        // Transport routing follows the viewed tab, not just the audio source.
        mainPlayerView.isViewingRadio = { [weak self] in
            self?.playlistView.isShowingRadio ?? false
        }
        let routesToRadio: () -> Bool = { [weak self, weak audioEngine] in
            audioEngine?.activeSource == .stream
                || self?.playlistView.isShowingRadio == true
        }

        // Mini-transport baked into pledit.bmp's BR corner mirrors the
        // main TransportBar — same play/pause/stop/prev/next semantics
        // as MainPlayerView, including radio routing by source or viewed tab.
        playlistView.onMiniPrev  = { [weak playlistManager, weak radioManager] in
            if routesToRadio() {
                Task { await radioManager?.playPrevious() }
            } else {
                playlistManager?.playPrevious()
            }
        }
        playlistView.onMiniPlay  = { [weak audioEngine, weak playlistManager] in
            guard let engine = audioEngine else { return }
            if engine.activeSource == .stream {
                if engine.playState != .playing { engine.replayCurrentStream() }
                return
            }
            if engine.playState == .stopped, let pm = playlistManager, pm.currentTrack != nil {
                // playTrack honors CUE segment bounds (a bare loadAndPlay(url:)
                // would play the whole album file) and re-arms gapless chaining.
                pm.playTrack(at: pm.currentIndex)
            } else {
                engine.play()
            }
        }
        playlistView.onMiniPause = { [weak audioEngine] in audioEngine?.pause() }
        playlistView.onMiniStop  = { [weak audioEngine] in audioEngine?.stop() }
        playlistView.onMiniNext  = { [weak playlistManager, weak radioManager] in
            if routesToRadio() {
                Task { await radioManager?.playNext() }
            } else {
                playlistManager?.playNext()
            }
        }

        mainPlayerView.onToggleEQ = { [weak self] in
            self?.showEqualizer.toggle()
        }
        mainPlayerView.onTogglePL = { [weak self] in
            self?.showPlaylist.toggle()
        }
        mainPlayerView.onWindowShade = { [weak self] in
            self?.toggleWindowShade()
        }
    }

    /// Applies the non-rectangular window mask from the current skin's region.txt.
    /// Called by AppDelegate after each skin load/unload.
    ///
    /// The mask is scoped to `mainPlayerView` because region.txt describes the
    /// 275×116 main-player window only — EQ and playlist stay rectangular. We
    /// also flip the window to non-opaque while a region is active, otherwise
    /// the NSWindow background fills the cutout areas and the silhouette looks
    /// pasted onto a solid rectangle instead of showing the desktop behind it.
    func applyRegionMaskFromCurrentSkin() {
        mainPlayerView.wantsLayer = true

        if let region = SkinManager.shared.currentSkin.mainWindowRegion {
            let mask = CAShapeLayer()
            mask.path = region.cgPath
            mask.fillColor = NSColor.black.cgColor
            // Match the backing scale so the mask rasterises at physical-pixel resolution
            // on Retina displays instead of upscaling a 1× bitmap.
            mask.contentsScale = backingScaleFactor
            mainPlayerView.layer?.mask = mask
            isOpaque = false
            backgroundColor = .clear
        } else {
            mainPlayerView.layer?.mask = nil
            isOpaque = true
            backgroundColor = WinampTheme.frameBackground
        }
        invalidateShadow()
    }
}
