import Cocoa
import Combine
import UniformTypeIdentifiers


class MainPlayerView: NSView {
    // Callbacks
    var onToggleEQ: (() -> Void)?
    var onTogglePL: (() -> Void)?
    var onWindowShade: (() -> Void)?

    var isEQActive: Bool {
        get { eqButton.isActive }
        set { eqButton.isActive = newValue }
    }
    var isPLActive: Bool {
        get { plButton.isActive }
        set { plButton.isActive = newValue }
    }

    /// When true the player collapses to the windowshade strip: the body is
    /// hidden and only a title bar with a scrolling title, compact time, and
    /// mini seek remains. Driven by `MainWindow.windowShade`.
    var isWindowShade: Bool = false {
        didSet {
            guard isWindowShade != oldValue else { return }
            applyVisibility()
            needsLayout = true
            needsDisplay = true
        }
    }

    // Subviews
    private let titleBar = TitleBarView()
    private let timeDisplay = SevenSegmentView()
    private let spectrumView = SpectrumView()
    private let lcdDisplay = LCDDisplay()
    private let seekSlider = WinampSlider(style: .seek)
    private let volumeSlider = WinampSlider(style: .volume)
    private let balanceSlider = WinampSlider(style: .balance)
    private let transportBar = TransportBar()

    // Toggle buttons
    private let shuffleButton = WinampButton(title: "", style: .toggle)
    private let repeatButton = WinampButton(title: "", style: .toggle)
    private let eqButton = WinampButton(title: "EQ", style: .toggle)
    private let plButton = WinampButton(title: "PL", style: .toggle)

    // Info labels
    private let bitrateLabel = NSTextField(labelWithString: "")
    private let sampleRateLabel = NSTextField(labelWithString: "")
    private let bitrateUnitLabel = NSTextField(labelWithString: "kbps")
    private let sampleRateUnitLabel = NSTextField(labelWithString: "khz")
    private let monoLabel = NSTextField(labelWithString: "mono")
    private let stereoLabel = NSTextField(labelWithString: "stereo")

    // Panel backgrounds
    private let leftPanel = NSView()
    private let rightPanel = NSView()


    // Play state indicator
    private let playIndicator = PlayStateIndicator()

    // Invisible click hit-zones for close/minimize/shade/menu when skinned (replace hidden titleBar)
    private let closeHitZone = NSView()
    private let minimizeHitZone = NSView()
    private let shadeHitZone = NSView()
    private let menuHitZone = NSView()
    // Click target over the Nullsoft logo baked into main.bmp, right of the repeat button.
    private let githubHitZone = NSView()

    private var cancellables = Set<AnyCancellable>()
    private var skinObserver: AnyCancellable?
    private weak var audioEngine: AudioEngine?
    private weak var playlistManager: PlaylistManager?
    private weak var radioManager: RadioManager?

    /// Supplied by MainWindow: whether the playlist panel shows the Radio tab.
    var isViewingRadio: (() -> Bool)?

    /// Transport next/prev drive the radio list when a stream is the active
    /// source or the user is viewing the Radio tab.
    private var routesToRadio: Bool {
        audioEngine?.activeSource == .stream || isViewingRadio?() == true
    }

    // Window dragging state for skinned mode (titleBar is hidden)
    private var dragOrigin: NSPoint?

    /// View height in logical (pre-scale) points. Winamp's main.bmp is exactly
    /// 116 px tall, so when a skin is active we shrink the view to match and
    /// lay out subviews at the sprite's native pixel coordinates. When no skin
    /// is loaded, we use Wamp's original 126 px layout.
    var desiredHeight: CGFloat {
        if isWindowShade { return WinampTheme.shadeHeight }
        return WinampTheme.skinIsActive ? 116 : WinampTheme.mainPlayerHeight
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor
        setupSubviews()
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyVisibility()
                self?.needsDisplay = true
                self?.needsLayout = true
            }
        applyVisibility()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSubviews() {
        // Title bar
        titleBar.titleText = "WAMP"
        titleBar.showButtons = true
        titleBar.onClose = { NSApp.terminate(nil) }
        titleBar.onMinimize = { [weak self] in self?.window?.miniaturize(nil) }
        titleBar.onWindowShade = { [weak self] in self?.onWindowShade?() }
        titleBar.onMenuClick = { [weak self] in self?.showWindowMenu() }
        addSubview(titleBar)

        // Left display panel background
        leftPanel.wantsLayer = true
        leftPanel.layer?.backgroundColor = NSColor.black.cgColor
        addSubview(leftPanel)


        // Time display
        timeDisplay.wantsLayer = true
        addSubview(timeDisplay)
        addSubview(playIndicator)

        // Spectrum
        spectrumView.wantsLayer = true
        addSubview(spectrumView)

        // Right display panel
        rightPanel.wantsLayer = true
        rightPanel.layer?.backgroundColor = NSColor.black.cgColor
        addSubview(rightPanel)

        // LCD (track title)
        addSubview(lcdDisplay)

        // Info labels
        for label in [bitrateLabel, sampleRateLabel, bitrateUnitLabel, sampleRateUnitLabel, monoLabel, stereoLabel] {
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            label.font = WinampTheme.bitrateFont
            label.textColor = WinampTheme.greenDimText
            addSubview(label)
        }

        // Seek slider
        seekSlider.maxValue = 1
        addSubview(seekSlider)

        // Volume
        volumeSlider.value = 0.75
        volumeSlider.maxValue = 1
        addSubview(volumeSlider)

        // Balance
        balanceSlider.value = 0.5
        balanceSlider.minValue = 0
        balanceSlider.maxValue = 1
        addSubview(balanceSlider)

        // Transport bar
        addSubview(transportBar)

        // Shuffle button (crossing arrows icon)
        shuffleButton.drawIcon = { rect, active in
            let color = active ? WinampTheme.buttonTextActive : WinampTheme.buttonTextInactive
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.move(to: NSPoint(x: rect.minX + 1, y: rect.midY - 2))
            path.line(to: NSPoint(x: rect.midX, y: rect.midY + 2))
            path.line(to: NSPoint(x: rect.maxX - 1, y: rect.midY - 2))
            path.stroke()
            let path2 = NSBezierPath()
            path2.lineWidth = 1.2
            path2.move(to: NSPoint(x: rect.minX + 1, y: rect.midY + 2))
            path2.line(to: NSPoint(x: rect.midX, y: rect.midY - 2))
            path2.line(to: NSPoint(x: rect.maxX - 1, y: rect.midY + 2))
            path2.stroke()
        }
        addSubview(shuffleButton)

        // Repeat button (loop arrows icon)
        repeatButton.drawIcon = { [weak self] rect, active in
            let color = active ? WinampTheme.buttonTextActive : WinampTheme.buttonTextInactive
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.2
            // Top arrow going right
            path.move(to: NSPoint(x: rect.minX + 2, y: rect.midY + 1))
            path.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY + 1))
            path.stroke()
            // Arrow head right
            let arr1 = NSBezierPath()
            arr1.lineWidth = 1.2
            arr1.move(to: NSPoint(x: rect.maxX - 4, y: rect.midY + 3))
            arr1.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY + 1))
            arr1.line(to: NSPoint(x: rect.maxX - 4, y: rect.midY - 1))
            arr1.stroke()
            // Bottom arrow going left
            let path2 = NSBezierPath()
            path2.lineWidth = 1.2
            path2.move(to: NSPoint(x: rect.maxX - 2, y: rect.midY - 2))
            path2.line(to: NSPoint(x: rect.minX + 2, y: rect.midY - 2))
            path2.stroke()
            // Arrow head left
            let arr2 = NSBezierPath()
            arr2.lineWidth = 1.2
            arr2.move(to: NSPoint(x: rect.minX + 4, y: rect.midY))
            arr2.line(to: NSPoint(x: rect.minX + 2, y: rect.midY - 2))
            arr2.line(to: NSPoint(x: rect.minX + 4, y: rect.midY - 4))
            arr2.stroke()
            // Draw "1" for single-track repeat mode
            if self?.audioEngine?.repeatMode == .track {
                let font = NSFont.monospacedSystemFont(ofSize: 5.5, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                let str = "1"
                let size = str.size(withAttributes: attrs)
                let point = NSPoint(
                    x: rect.maxX - size.width + 2,
                    y: rect.minY - 3
                )
                str.draw(at: point, withAttributes: attrs)
            }
        }
        addSubview(repeatButton)

        // EQ / PL buttons
        eqButton.isActive = true
        plButton.isActive = true
        addSubview(eqButton)
        addSubview(plButton)

        // Wire skin sprite keys for the four toggle buttons
        shuffleButton.spriteKeyProvider = { active, pressed in .shuffleButton(active: active, pressed: pressed) }
        repeatButton.spriteKeyProvider  = { active, pressed in .repeatButton(active: active, pressed: pressed) }
        eqButton.spriteKeyProvider      = { active, pressed in .eqToggleButton(active: active, pressed: pressed) }
        plButton.spriteKeyProvider      = { active, pressed in .plToggleButton(active: active, pressed: pressed) }

        // Button actions
        shuffleButton.onClick = { [weak self] in
            self?.playlistManager?.shuffleTracks()
        }
        repeatButton.onClick = { [weak self] in
            guard let engine = self?.audioEngine else { return }
            let next = RepeatMode(rawValue: (engine.repeatMode.rawValue + 1) % 3) ?? .off
            engine.repeatMode = next
        }
        eqButton.onClick = { [weak self] in self?.onToggleEQ?() }
        plButton.onClick = { [weak self] in self?.onTogglePL?() }

        // Click hit-zones for close/minimize/menu when skinned (titleBar is hidden
        // then, so we need invisible NSViews at the locations where main.bmp paints
        // these buttons so the user can still interact with them).
        addSubview(closeHitZone)
        addSubview(minimizeHitZone)
        addSubview(shadeHitZone)
        addSubview(menuHitZone)
        addSubview(githubHitZone)
        let closeClick = NSClickGestureRecognizer(target: self, action: #selector(handleSkinnedClose))
        closeHitZone.addGestureRecognizer(closeClick)
        let minimizeClick = NSClickGestureRecognizer(target: self, action: #selector(handleSkinnedMinimize))
        minimizeHitZone.addGestureRecognizer(minimizeClick)
        let shadeClick = NSClickGestureRecognizer(target: self, action: #selector(handleSkinnedShade))
        shadeHitZone.addGestureRecognizer(shadeClick)
        let menuClick = NSClickGestureRecognizer(target: self, action: #selector(handleSkinnedMenu))
        menuHitZone.addGestureRecognizer(menuClick)
        let githubClick = NSClickGestureRecognizer(target: self, action: #selector(handleOpenGitHub))
        githubHitZone.addGestureRecognizer(githubClick)
    }

    @objc private func handleSkinnedClose() { NSApp.terminate(nil) }
    @objc private func handleSkinnedMinimize() { window?.miniaturize(nil) }
    @objc private func handleSkinnedShade() { onWindowShade?() }
    @objc private func handleSkinnedMenu() { showWindowMenu() }
    @objc private func handleOpenGitHub() {
        if let url = URL(string: "https://github.com/abiheiri/wamp") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Resolves subview visibility from two axes: whether a skin is loaded
    /// (chrome baked into main.bmp / monoster.bmp / text.bmp is hidden — spec §8)
    /// and whether the window is collapsed to the shade strip (the whole body is
    /// hidden, leaving only the title bar + scrolling title / time / mini seek).
    private func applyVisibility() {
        let skin = WinampTheme.skinIsActive
        let shade = isWindowShade

        // Unskinned title-bar chrome. In shade it becomes the collapsed strip.
        titleBar.isHidden = skin
        titleBar.showMenuIcon = !skin
        titleBar.compactStrip = shade

        // Body controls — present only in the full (non-shade) player.
        spectrumView.isHidden = shade
        volumeSlider.isHidden = shade
        balanceSlider.isHidden = shade
        seekSlider.isHidden = shade
        transportBar.isHidden = shade
        shuffleButton.isHidden = shade
        repeatButton.isHidden = shade
        eqButton.isHidden = shade
        plButton.isHidden = shade

        // Skin-baked chrome — hidden when skinned, and also while shaded.
        leftPanel.isHidden = skin || shade
        rightPanel.isHidden = skin || shade
        for label in [bitrateLabel, sampleRateLabel, bitrateUnitLabel, sampleRateUnitLabel, monoLabel, stereoLabel] {
            label.isHidden = skin || shade
        }
        playIndicator.isHidden = skin || shade

        // The scrolling title and time appear in both the full player and the
        // shade strip, so they stay visible in every mode.
        lcdDisplay.isHidden = false
        timeDisplay.isHidden = false

        // Skinned-mode click hit-zones (the title bar is hidden when skinned).
        closeHitZone.isHidden = !skin
        minimizeHitZone.isHidden = !skin
        shadeHitZone.isHidden = !skin
        menuHitZone.isHidden = !skin
        githubHitZone.isHidden = !skin || shade
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard WinampTheme.skinIsActive else { return }
        drawSkinned()
    }

    private func drawSkinned() {
        let ctx = NSGraphicsContext.current
        let prevInterp = ctx?.imageInterpolation
        let prevAA = ctx?.shouldAntialias
        ctx?.imageInterpolation = .none
        ctx?.shouldAntialias = false
        defer {
            if let v = prevInterp { ctx?.imageInterpolation = v }
            if let v = prevAA { ctx?.shouldAntialias = v }
        }

        if isWindowShade { drawSkinnedShade(); return }

        // View is resized to 116 px (native main.bmp height) when skinned,
        // so the sprite fills bounds exactly and sub-sprite coordinates are
        // in the same space as Webamp's main-window.css.
        let mainHeight: CGFloat = bounds.height
        if let bg = WinampTheme.sprite(.mainBackground) {
            bg.draw(in: backingAlignedRect(bounds, options: .alignAllEdgesNearest))
        }

        // Title bar overlay (main.bmp leaves the top 14px empty for this).
        // Webamp y=0..14 (top-down) → AppKit y = mainHeight - 14.
        let isActive = window?.isKeyWindow ?? true
        if let tb = WinampTheme.sprite(isActive ? .titleBarActive : .titleBarInactive) {
            tb.draw(in: backingAlignedRect(NSRect(x: 0, y: mainHeight - 14, width: bounds.width, height: 14), options: .alignAllEdgesNearest))
        }

        // Mono / stereo sprites at fixed Webamp coordinates.
        // Webamp positions (top-down): mono at (212, 41) 27w, stereo at (239, 41) 29w, 12 px tall.
        // Convert to AppKit (bottom-up): y_appkit = mainHeight - 41 - 12
        let isStereo = playlistManager?.currentTrack?.isStereo ?? false
        let monoY: CGFloat = mainHeight - 41 - 12
        if let monoSprite = WinampTheme.sprite(.mono(active: !isStereo)) {
            monoSprite.draw(in: backingAlignedRect(NSRect(x: 212, y: monoY, width: 27, height: 12), options: .alignAllEdgesNearest))
        }
        if let stereoSprite = WinampTheme.sprite(.stereo(active: isStereo)) {
            stereoSprite.draw(in: backingAlignedRect(NSRect(x: 239, y: monoY, width: 29, height: 12), options: .alignAllEdgesNearest))
        }

        // Bitrate / sample rate digits via text.bmp.
        // The "kbps" and "khz" *labels* are baked into main.bmp, so only draw the numbers.
        // Webamp positions (top-down): bitrate at (111, 43), sample rate at (156, 43).
        // y_appkit = mainHeight - 43 - 6 (glyphs are 6 px tall) = 67
        if let track = playlistManager?.currentTrack {
            let textSheet = WinampTheme.provider.textSheet
            let textY: CGFloat = mainHeight - 43 - 6
            let bitrateStr = track.bitrate > 0 ? String(format: "%3d", track.bitrate) : "---"
            let sampleStr = track.sampleRate > 0 ? String(format: "%2d", track.sampleRate / 1000) : "--"
            TextSpriteRenderer.drawClassic(bitrateStr, at: NSPoint(x: 111, y: textY), sheet: textSheet)
            TextSpriteRenderer.drawClassic(sampleStr,  at: NSPoint(x: 156, y: textY), sheet: textSheet)
        }
    }

    override func layout() {
        super.layout()
        if isWindowShade {
            layoutShade()
        } else if WinampTheme.skinIsActive {
            layoutSkinned()
        } else {
            layoutUnskinned()
        }
    }

    /// The recessed black readout inset of the skinned shade strip. Sits between
    /// the left options button and the right min/shade/close cluster, covering
    /// the skin's baked title/logo so it doesn't compete with our overlays.
    private func shadeReadoutPanel() -> NSRect {
        // Right edge butts against the baked minimize button (x≈243) so no
        // baked title-bar decoration peeks through beside the button cluster.
        NSRect(x: 16, y: (bounds.height - 10) / 2, width: 226, height: 10)
    }

    /// Draws the collapsed windowshade strip when a skin is active. Uses the
    /// normal (decorated) title bar so its baked-in window buttons — including
    /// the windowshade button — keep their usual bitmaps, then lays a recessed
    /// black panel over the center for the scrolling title + time subviews.
    private func drawSkinnedShade() {
        let isActive = window?.isKeyWindow ?? true
        WinampTheme.sprite(isActive ? .titleBarActive : .titleBarInactive)?
            .draw(in: backingAlignedRect(bounds, options: .alignAllEdgesNearest))

        NSColor.black.setFill()
        shadeReadoutPanel().fill()
    }

    /// Lays out the collapsed strip. Unskinned, the title bar draws the chrome +
    /// buttons and the scrolling title / time overlay it directly. Skinned, the
    /// readout sits inside the recessed panel and invisible hit-zones cover the
    /// title bar's baked min / windowshade / close buttons.
    private func layoutShade() {
        let w = bounds.width
        let h = bounds.height

        titleBar.frame = NSRect(x: 0, y: 0, width: w, height: h)

        if WinampTheme.skinIsActive {
            let panel = shadeReadoutPanel()
            let timeW: CGFloat = 42, timeH: CGFloat = 9
            let timeX = panel.maxX - timeW - 2
            timeDisplay.frame = NSRect(x: timeX, y: (h - timeH) / 2, width: timeW, height: timeH)
            timeDisplay.layer?.backgroundColor = NSColor.clear.cgColor

            let titleX = panel.minX + 4
            lcdDisplay.frame = NSRect(x: titleX, y: (h - 7) / 2, width: max(10, timeX - titleX - 6), height: 7)

            // Hit-zones over the baked min / windowshade / close buttons.
            let by = (h - 9) / 2
            minimizeHitZone.frame = NSRect(x: 243, y: by, width: 11, height: 9)
            shadeHitZone.frame    = NSRect(x: 254, y: by, width: 9,  height: 9)
            closeHitZone.frame    = NSRect(x: 263, y: by, width: 11, height: 9)
            menuHitZone.frame     = NSRect(x: 6, y: by, width: 9, height: 9)
        } else {
            let buttonsLeft = w - 36
            let menuLeft: CGFloat = 12  // clear the unskinned menu icon at x≈3–12
            let timeW: CGFloat = 34, timeH: CGFloat = 9
            let timeX = buttonsLeft - timeW - 2
            timeDisplay.frame = NSRect(x: timeX, y: (h - timeH) / 2, width: timeW, height: timeH)
            timeDisplay.layer?.backgroundColor = NSColor.black.cgColor

            let titleW = max(10, timeX - menuLeft - 6)
            lcdDisplay.frame = NSRect(x: menuLeft, y: (h - 9) / 2, width: titleW, height: 9)
        }
        githubHitZone.frame = .zero
    }

    /// Exact Winamp 2.x pixel coordinates, ported from Webamp's main-window.css.
    /// View bounds are 275×116 in this mode; Y is converted from Webamp (top-down)
    /// to AppKit (bottom-up) as: y_appkit = 116 - y_webamp - height.
    private func layoutSkinned() {
        let h: CGFloat = bounds.height  // 116

        // Title bar (hidden, but keep frame valid)
        titleBar.frame = NSRect(x: 0, y: h - 16, width: bounds.width, height: 16)

        // Close / windowshade / minimize hit-zones — webamp close(264,3), shade(254,3),
        // min(244,3), each 9×9. The shade zone sits between min and close.
        let hitSize: CGFloat = 11
        let hitY = h - 3 - hitSize
        closeHitZone.frame = NSRect(x: 263, y: hitY, width: hitSize, height: hitSize)
        shadeHitZone.frame = NSRect(x: 254, y: hitY, width: 9, height: hitSize)
        minimizeHitZone.frame = NSRect(x: 243, y: hitY, width: hitSize, height: hitSize)

        // Menu icon hit-zone — webamp top-left icon at (6, 3, 9×9)
        menuHitZone.frame = NSRect(x: 6, y: hitY, width: hitSize, height: hitSize)

        // Hidden panels — collapse
        leftPanel.frame = .zero
        rightPanel.frame = .zero
        for label in [bitrateLabel, sampleRateLabel, bitrateUnitLabel, sampleRateUnitLabel, monoLabel, stereoLabel] {
            label.frame = .zero
        }

        // 7-segment time (webamp #time at 39,26,59,13 → y=77; widened 1px to fit last digit)
        timeDisplay.frame = NSRect(x: 39, y: 77, width: 60, height: 13)
        // Spectrum / visualizer (webamp 24,43,76,16 → y=57)
        spectrumView.frame = NSRect(x: 24, y: 57, width: 76, height: 16)
        // Scrolling track-title marquee (webamp 111,27,154,6 → y=83)
        lcdDisplay.frame = NSRect(x: 111, y: 83, width: 154, height: 6)

        // Seek/posbar (webamp 16,72,248,10 → y=34)
        seekSlider.frame = NSRect(x: 16, y: 34, width: 248, height: 10)

        // Volume / balance (webamp 107/177,57,68/38,13 → y=46)
        volumeSlider.frame = NSRect(x: 107, y: 46, width: 68, height: 13)
        balanceSlider.frame = NSRect(x: 177, y: 46, width: 38, height: 13)

        // EQ / PL toggle buttons (webamp 219/242,58,23,12 → y=46)
        eqButton.frame = NSRect(x: 219, y: 46, width: 23, height: 12)
        plButton.frame = NSRect(x: 242, y: 46, width: 23, height: 12)

        // Transport (cbuttons, webamp 16,88,*,18 → y=10). Width = sum of 5 buttons + eject.
        transportBar.frame = NSRect(x: 16, y: 10, width: transportBar.intrinsicContentSize.width, height: 18)

        // Shuffle / repeat (webamp 164,89,47,15 and 210,89,28,15 → y=12)
        shuffleButton.frame = NSRect(x: 164, y: 12, width: 47, height: 15)
        repeatButton.frame = NSRect(x: 210, y: 12, width: 28, height: 15)

        // Nullsoft logo (baked into main.bmp at ~249,89,18,15) — repurposed as a link to the repo.
        githubHitZone.frame = NSRect(x: 249, y: 12, width: 18, height: 15)
    }

    private func layoutUnskinned() {
        let w = bounds.width
        let pad: CGFloat = 3

        // Title bar
        titleBar.frame = NSRect(x: 0, y: bounds.height - WinampTheme.titleBarHeight,
                                width: w, height: WinampTheme.titleBarHeight)

        let contentTop = titleBar.frame.minY - pad
        let leftPanelW: CGFloat = 110
        let rightPanelX = leftPanelW + pad + pad
        let rightPanelW = w - rightPanelX - pad
        let displayH: CGFloat = 56

        // Left panel (black bg)
        leftPanel.frame = NSRect(x: pad, y: contentTop - displayH, width: leftPanelW, height: displayH)

        // Time + play state top row (inside left panel area)
        let timeH: CGFloat = 23
        let timeSpecGap: CGFloat = 6
        let specH = displayH - timeH - timeSpecGap - 2

        let indicatorW: CGFloat = 11
        let indicatorGap: CGFloat = 3
        let indicatorLeftInset: CGFloat = 8
        playIndicator.frame = NSRect(x: pad + indicatorLeftInset, y: contentTop - timeH + (timeH - indicatorW) / 2 - 2, width: indicatorW, height: indicatorW)
        let timeX = pad + indicatorLeftInset + indicatorW + indicatorGap
        timeDisplay.frame = NSRect(x: timeX, y: contentTop - timeH - 2, width: leftPanelW - (timeX - pad) - 2, height: timeH)
        spectrumView.frame = NSRect(x: pad + 2, y: contentTop - displayH + 2, width: leftPanelW - 4, height: specH)


        // Right panel (black bg)
        rightPanel.frame = NSRect(x: rightPanelX, y: contentTop - displayH, width: rightPanelW, height: displayH)

        // LCD display
        lcdDisplay.frame = NSRect(x: rightPanelX + 4, y: contentTop - 22, width: rightPanelW - 8, height: 16)

        // Bitrate info
        bitrateLabel.frame = NSRect(x: rightPanelX + 4, y: contentTop - 42, width: 22, height: 12)
        bitrateUnitLabel.frame = NSRect(x: rightPanelX + 22, y: contentTop - 42, width: 22, height: 12)
        sampleRateLabel.frame = NSRect(x: rightPanelX + 48, y: contentTop - 42, width: 18, height: 12)
        sampleRateUnitLabel.frame = NSRect(x: rightPanelX + 63, y: contentTop - 42, width: 20, height: 12)
        monoLabel.frame = NSRect(x: rightPanelX + rightPanelW - 50, y: contentTop - 42, width: 22, height: 12)
        stereoLabel.frame = NSRect(x: rightPanelX + rightPanelW - 28, y: contentTop - 42, width: 28, height: 12)

        let controlsTop = contentTop - displayH - 3

        // Seek bar
        seekSlider.frame = NSRect(x: pad, y: controlsTop - 10, width: w - 2 * pad, height: 10)

        // Volume + Balance (balance ~half the width of volume) with a right-side EQ/PL strip
        let sliderTop = controlsTop - 14
        let eqPlBtnW: CGFloat = 22
        let eqPlBtnH: CGFloat = 12
        let eqPlGap: CGFloat = 2
        let eqPlStripW = eqPlBtnW * 2 + eqPlGap
        let slidersRightEdge = w - pad - eqPlStripW - 4
        let slidersAvailW = slidersRightEdge - pad
        let sliderGap: CGFloat = 4
        let volumeW = floor((slidersAvailW - sliderGap) * 2 / 3)
        let balanceW = slidersAvailW - sliderGap - volumeW
        volumeSlider.frame = NSRect(x: pad, y: sliderTop - 8, width: volumeW, height: 8)
        balanceSlider.frame = NSRect(x: pad + volumeW + sliderGap, y: sliderTop - 8, width: balanceW, height: 8)

        // EQ / PL right-aligned on the slider row, vertically centered on the 8px slider strip
        let eqPlY = sliderTop - 8 + (8 - eqPlBtnH) / 2
        eqButton.frame = NSRect(x: w - pad - eqPlStripW, y: eqPlY, width: eqPlBtnW, height: eqPlBtnH)
        plButton.frame = NSRect(x: w - pad - eqPlBtnW,   y: eqPlY, width: eqPlBtnW, height: eqPlBtnH)

        // Transport row
        let transportTop = sliderTop - 12
        transportBar.frame = NSRect(x: pad, y: transportTop - 18, width: transportBar.intrinsicContentSize.width, height: 18)

        // Right side of transport row: shuffle, repeat only (EQ/PL moved up to the slider row)
        let btnH: CGFloat = 16
        let btnW: CGFloat = 20
        let toggleX = w - pad - (btnW * 2 + 1)
        let toggleY = transportTop - btnH - 1

        shuffleButton.frame = NSRect(x: toggleX, y: toggleY, width: btnW, height: btnH)
        repeatButton.frame = NSRect(x: toggleX + btnW + 1, y: toggleY, width: btnW, height: btnH)

        // Click hit-zones at the locations where main.bmp paints close/minimize.
        // Webamp positions (top-down): close at (264, 3), minimize at (244, 3), 9×9.
        // y_appkit = 116 - 3 - 9 = 104. Made slightly larger for easier clicking.
        let hitSize: CGFloat = 11
        let hitY: CGFloat = 116 - 3 - hitSize
        closeHitZone.frame = NSRect(x: 263, y: hitY, width: hitSize, height: hitSize)
        minimizeHitZone.frame = NSRect(x: 243, y: hitY, width: hitSize, height: hitSize)
        menuHitZone.frame = .zero
        githubHitZone.frame = .zero
    }

    // MARK: - Binding
    func bindToModels(audioEngine: AudioEngine, playlistManager: PlaylistManager, radioManager: RadioManager) {
        self.audioEngine = audioEngine
        self.playlistManager = playlistManager
        self.radioManager = radioManager

        // Time
        audioEngine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in self?.timeDisplay.timeInSeconds = time }
            .store(in: &cancellables)

        // Spectrum
        audioEngine.$spectrumData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.spectrumView.spectrumData = data }
            .store(in: &cancellables)

        // Stream info: the connecting/playing/failed phase, live ICY now-playing,
        // and active-source flips all drive the persistent marquee.
        Publishers.Merge3(
            audioEngine.$streamPhase.map { _ in () },
            audioEngine.$streamErrorText.map { _ in () },
            audioEngine.$streamNowPlaying.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard self?.audioEngine?.activeSource == .stream else { return }
            self?.updateTrackInfo()
            self?.needsDisplay = true
        }
        .store(in: &cancellables)

        audioEngine.$activeSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTrackInfo()
                self?.needsDisplay = true
            }
            .store(in: &cancellables)

        // Browse feedback (loading a genre, result counts) is transient — flash it
        // over the LCD. Connecting/playing/errors are persistent (handled above).
        // dropFirst skips the idle default shown at launch.
        radioManager.$statusMessage
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                guard !msg.isEmpty else { return }
                self?.lcdDisplay.showOverlay(msg, duration: 2.0)
            }
            .store(in: &cancellables)

        // Track info
        playlistManager.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTrackInfo() }
            .store(in: &cancellables)

        // Re-format the LCD title when a skin is loaded or unloaded, since
        // skinned mode omits the track-number prefix and duration suffix.
        SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTrackInfo() }
            .store(in: &cancellables)

        // Seek slider
        audioEngine.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in self?.seekSlider.maxValue = Float(dur) }
            .store(in: &cancellables)

        audioEngine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self, self.seekSlider.window != nil else { return }
                guard !self.seekSlider.isUserInteracting else { return }
                self.seekSlider.value = Float(time)
            }
            .store(in: &cancellables)

        seekSlider.onChange = { [weak audioEngine] value in
            audioEngine?.seek(to: TimeInterval(value))
        }

        // Volume
        volumeSlider.value = audioEngine.volume
        volumeSlider.onChange = { [weak self, weak audioEngine] value in
            audioEngine?.volume = value
            self?.lcdDisplay.showOverlay("Volume: \(Int(round(value * 100)))%")
        }

        // Balance
        balanceSlider.value = (audioEngine.balance + 1) / 2 // convert -1..1 to 0..1
        balanceSlider.onChange = { [weak audioEngine] value in
            audioEngine?.balance = value * 2 - 1 // convert 0..1 to -1..1
        }

        // Transport — routes to the radio list when a stream is playing OR the
        // playlist panel is on the Radio tab, so next/prev step through the
        // station list you're viewing (favorites or a genre).
        transportBar.onPrevious = { [weak self] in
            guard let self else { return }
            if self.routesToRadio {
                Task { await self.radioManager?.playPrevious() }
            } else {
                self.playlistManager?.playPrevious()
            }
        }
        transportBar.onPlay = { [weak self] in
            guard let self, let engine = self.audioEngine else { return }
            if engine.activeSource == .stream {
                // Live stream: reconnect from a stop; nothing to do while playing.
                if engine.playState != .playing { engine.replayCurrentStream() }
                return
            }
            if engine.playState == .stopped,
               let pm = self.playlistManager, pm.currentTrack != nil {
                // playTrack honors CUE segment bounds (a bare loadAndPlay(url:)
                // would play the whole album file) and re-arms gapless chaining.
                pm.playTrack(at: pm.currentIndex)
            } else {
                engine.play()
            }
        }
        transportBar.onPause = { [weak audioEngine] in audioEngine?.pause() }
        transportBar.onStop = { [weak audioEngine] in audioEngine?.stop() }
        transportBar.onNext = { [weak self] in
            guard let self else { return }
            if self.routesToRadio {
                Task { await self.radioManager?.playNext() }
            } else {
                self.playlistManager?.playNext()
            }
        }
        transportBar.onEject = { [weak self] in self?.showOpenFilePanel() }

        // Play state
        audioEngine.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                self?.transportBar.playButton.isActive = playing
            }
            .store(in: &cancellables)

        audioEngine.$playState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.playIndicator.state = state
            }
            .store(in: &cancellables)

        // Repeat state
        audioEngine.$repeatMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.repeatButton.isActive = mode != .off
                self?.repeatButton.needsDisplay = true
            }
            .store(in: &cancellables)
    }

    private func updateTrackInfo() {
        if audioEngine?.activeSource == .stream {
            updateStreamInfo()
            return
        }
        guard let track = playlistManager?.currentTrack else {
            lcdDisplay.text = ""
            bitrateLabel.stringValue = ""
            sampleRateLabel.stringValue = ""
            return
        }
        let index = (playlistManager?.currentIndex ?? 0) + 1
        // Skinned LCD is 6px-glyph text.bmp — just show the title.
        // The track number is redundant (playlist shows it), and the duration
        // is redundant (7-segment display shows it).
        lcdDisplay.text = WinampTheme.skinIsActive
            ? track.displayTitle
            : "\(index). \(track.displayTitle) (\(track.formattedDuration))"
        bitrateLabel.stringValue = "\(track.bitrate > 0 ? "\(track.bitrate)" : "---")"
        bitrateLabel.textColor = WinampTheme.greenBright
        sampleRateLabel.stringValue = "\(track.sampleRate > 0 ? "\(track.sampleRate / 1000)" : "--")"
        sampleRateLabel.textColor = WinampTheme.greenBright
        stereoLabel.textColor = track.isStereo ? WinampTheme.greenBright : WinampTheme.greenDimText
        monoLabel.textColor = track.isStereo ? WinampTheme.greenDimText : WinampTheme.greenBright
        // Force redraw so skinned kbps/khz text updates immediately.
        needsDisplay = true
    }

    /// Persistent marquee for the active SHOUTcast stream, driven by the stream
    /// lifecycle: connecting → playing (live ICY title, or station name until
    /// metadata arrives) → a friendly error line on failure.
    private func updateStreamInfo() {
        let station = radioManager?.currentStation
        let name = station?.name ?? "SHOUTcast Stream"
        switch audioEngine?.streamPhase ?? .idle {
        case .connecting:
            lcdDisplay.text = "Connecting to \(name)…"
        case .playing:
            let nowPlaying = audioEngine?.streamNowPlaying ?? ""
            lcdDisplay.text = nowPlaying.isEmpty ? name : "\(name): \(nowPlaying)"
        case .failed:
            let detail = audioEngine?.streamErrorText ?? ""
            lcdDisplay.text = detail.isEmpty ? "Couldn't play \(name)" : detail
        case .idle:
            lcdDisplay.text = name
        }
        let br = station?.bitrate ?? 0
        bitrateLabel.stringValue = br > 0 ? "\(br)" : "---"
        bitrateLabel.textColor = WinampTheme.greenBright
        sampleRateLabel.stringValue = "--"
        sampleRateLabel.textColor = WinampTheme.greenBright
        stereoLabel.textColor = WinampTheme.greenBright
        monoLabel.textColor = WinampTheme.greenDimText
    }

    private func showWindowMenu() {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        let menu = delegate.buildCornerPopupMenu()
        let anchor = NSPoint(x: titleBar.frame.minX, y: titleBar.frame.minY)
        menu.popUp(positioning: nil, at: anchor, in: self)
    }

    private func showOpenFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                for url in panel.urls {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        await self?.playlistManager?.addFolder(url)
                    } else {
                        await self?.playlistManager?.addURLs([url])
                    }
                }
            }
        }
    }

    // MARK: - Window dragging (skinned mode)
    // When skinned, TitleBarView is hidden so we handle dragging from the title
    // bar area (top 14px of the 116px skin) directly in MainPlayerView.

    override func mouseDown(with event: NSEvent) {
        guard WinampTheme.skinIsActive else { super.mouseDown(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        let titleBarMinY = bounds.height - 14
        guard point.y >= titleBarMinY else { super.mouseDown(with: event); return }
        // Don't drag from close/minimize/menu hit-zones
        if closeHitZone.frame.contains(point) || minimizeHitZone.frame.contains(point)
            || menuHitZone.frame.contains(point) {
            super.mouseDown(with: event)
            return
        }
        dragOrigin = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let win = window else { return }
        let current = event.locationInWindow
        var frame = win.frame
        frame.origin.x += current.x - origin.x
        frame.origin.y += current.y - origin.y
        win.setFrameOrigin(frame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        super.mouseUp(with: event)
    }
}
