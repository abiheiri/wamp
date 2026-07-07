import Cocoa
import Combine

class SpectrumView: NSView {
    var spectrumData: [Float] = [] {
        didSet {
            targetData = spectrumData
            startAnimationIfNeeded()
        }
    }
    var barCount: Int = 26

    /// Winamp convention: 16 vertical rows, each painted with viscolors[2..17] bottom→top.
    private static let rowCount = 16

    private var targetData: [Float] = []
    private var smoothedData: [Float] = []
    private var peakRows: [Float] = []
    private var peakHoldCounters: [Int] = []
    private var peakVelocities: [Float] = []
    private var animationTimer: Timer?
    private var skinObserver: AnyCancellable?

    // Fast attack, slow decay — classic Winamp feel
    private let riseCoeff: Float = 0.50
    private let fallCoeff: Float = 0.07

    // Peak cap: hold briefly, then fall with gravity (in row units)
    private let peakHoldFrames = 15
    private let peakGravity: Float = 0.02
    private let peakMaxVelocity: Float = 0.50

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
        resetArrays()
    }

    /// The timer only runs while there's something to animate. It stops itself
    /// once the bars and peak caps have decayed to zero (see `tick`), so a
    /// paused/stopped player costs no redraws; fresh spectrum data restarts it.
    private func startAnimationIfNeeded() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func resetArrays() {
        smoothedData = Array(repeating: 0, count: barCount)
        peakRows = Array(repeating: 0, count: barCount)
        peakHoldCounters = Array(repeating: 0, count: barCount)
        peakVelocities = Array(repeating: 0, count: barCount)
    }

    private func tick() {
        if smoothedData.count != barCount { resetArrays() }
        let input = targetData
        let rows = Float(Self.rowCount)
        for i in 0..<barCount {
            let srcIdx = input.isEmpty ? 0 : min(i * input.count / barCount, input.count - 1)
            let target = input.isEmpty ? Float(0) : min(1, input[srcIdx] * 10)
            let cur = smoothedData[i]
            smoothedData[i] = target > cur
                ? cur + (target - cur) * riseCoeff
                : cur + (target - cur) * fallCoeff

            let barRowsF = smoothedData[i] * rows
            if barRowsF >= peakRows[i] {
                peakRows[i] = barRowsF
                peakHoldCounters[i] = peakHoldFrames
                peakVelocities[i] = 0
            } else if peakHoldCounters[i] > 0 {
                peakHoldCounters[i] -= 1
            } else {
                peakVelocities[i] = min(peakMaxVelocity, peakVelocities[i] + peakGravity)
                peakRows[i] = max(0, peakRows[i] - peakVelocities[i])
            }
        }
        needsDisplay = true

        // Everything has decayed to silence — snap to zero, draw the empty
        // display once, and stop ticking until new spectrum data arrives.
        let epsilon: Float = 0.001
        let settled = input.allSatisfy { $0 <= epsilon }
            && smoothedData.allSatisfy { $0 <= epsilon }
            && peakRows.allSatisfy { $0 <= epsilon }
        if settled {
            resetArrays()
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard smoothedData.count == barCount else { return }

        let barWidth: CGFloat = 3
        let gap: CGFloat = 1
        let totalBars = min(barCount, Int(bounds.width / (barWidth + gap)))
        let rows = Self.rowCount
        let rowHeight = bounds.height / CGFloat(rows)

        let viscolors = WinampTheme.provider.viscolors
        guard viscolors.count >= 24 else { return }
        let peakColor = viscolors[23]

        for i in 0..<totalBars {
            let litRows = Int(smoothedData[i] * Float(rows))
            let x = CGFloat(i) * (barWidth + gap)

            // Discrete 16-step bar. Winamp's viscolor convention puts index 2
            // at the TOP row of the 16-row column; r counts bottom-up in
            // AppKit, so the index runs backwards.
            for r in 0..<litRows {
                viscolors[2 + (rows - 1 - r)].setFill()
                NSRect(x: x,
                       y: CGFloat(r) * rowHeight,
                       width: barWidth,
                       height: rowHeight).fill()
            }

            // Peak cap
            let peakRow = Int(peakRows[i])
            if peakRow > litRows && peakRow < rows {
                peakColor.setFill()
                NSRect(x: x,
                       y: CGFloat(peakRow) * rowHeight,
                       width: barWidth,
                       height: rowHeight).fill()
            }
        }
    }

    deinit {
        animationTimer?.invalidate()
    }
}
