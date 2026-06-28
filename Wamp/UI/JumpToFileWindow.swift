import Cocoa

/// Delegate that JumpToFileWindow calls back to. Implemented by AppDelegate.
protocol JumpToFileDelegate: AnyObject {
    /// All tracks in the playlist, in playlist order.
    var jumpCandidates: [JumpFilter.Candidate] { get }
    /// Index of the currently-playing track, or nil.
    var currentTrackIndex: Int? { get }
    /// Play the track at the given playlist index.
    func playTrack(atPlaylistIndex index: Int)
}

/// Cmd+J "Jump to" finder. Two tabs:
///  - Playlist: instant in-memory filter+rank of local tracks (`JumpFilter`).
///  - Radio: ephemeral directory-wide SHOUTcast search (debounced network) that
///    does not touch the panel's station list — picking a station just plays it.
final class JumpToFileWindow: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    weak var jumpDelegate: JumpToFileDelegate?
    weak var radioManager: RadioManager?

    private enum FinderMode: Int { case playlist = 0, radio = 1 }
    private var mode: FinderMode = .playlist

    private let tabs = NSSegmentedControl(labels: ["Playlist", "Radio"],
                                          trackingMode: .selectOne, target: nil, action: nil)
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let goToCurrentButton = NSButton(title: "Go to current", target: nil, action: nil)

    // Playlist state
    private var matches: [JumpFilter.Match] = []
    private var candidates: [JumpFilter.Candidate] = []

    // Radio state
    private var radioStations: [ShoutcastStation] = []
    private var radioSearchTask: Task<Void, Never>?
    private var radioDebounce: Timer?

    private var rowCount: Int { mode == .radio ? radioStations.count : matches.count }

    init() {
        let rect = NSRect(x: 0, y: 0, width: 500, height: 400)
        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Jump to"
        isFloatingPanel = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        setupContent()
    }

    override var canBecomeKey: Bool { true }

    private func setupContent() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        contentView = content

        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged)
        content.addSubview(tabs)

        // Search field
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Type to filter…"
        searchField.delegate = self
        content.addSubview(searchField)

        // Table — single column, no header
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.width = 480
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 18
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        if #available(macOS 11.0, *) { tableView.style = .plain }
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .regular

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        content.addSubview(scrollView)

        // Bottom bar
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        content.addSubview(statusLabel)

        goToCurrentButton.translatesAutoresizingMaskIntoConstraints = false
        goToCurrentButton.bezelStyle = .rounded
        goToCurrentButton.target = self
        goToCurrentButton.action = #selector(scrollToCurrent)
        content.addSubview(goToCurrentButton)

        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),

            searchField.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: goToCurrentButton.centerYAnchor),

            goToCurrentButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            goToCurrentButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
    }

    /// Reset and present, opening on the section matching what the panel shows.
    func present(over parent: NSWindow?, startInRadio: Bool = false) {
        mode = startInRadio ? .radio : .playlist
        tabs.selectedSegment = mode.rawValue
        candidates = jumpDelegate?.jumpCandidates ?? []
        radioStations = []
        searchField.stringValue = ""
        applyModeChrome()
        refreshResults()

        if let parent {
            let parentFrame = parent.frame
            setFrameOrigin(NSPoint(x: parentFrame.midX - frame.width / 2,
                                   y: parentFrame.midY - frame.height / 2))
        } else {
            center()
        }
        makeKeyAndOrderFront(nil)
        makeFirstResponder(searchField)

        // Playlist: pre-select the current track if it's visible.
        if mode == .playlist, let curIdx = jumpDelegate?.currentTrackIndex,
           let row = matches.firstIndex(where: { $0.index == curIdx }) {
            select(row)
        }
    }

    @objc private func tabChanged() {
        mode = FinderMode(rawValue: tabs.selectedSegment) ?? .playlist
        applyModeChrome()
        refreshResults()
    }

    /// Per-mode placeholder / button visibility.
    private func applyModeChrome() {
        switch mode {
        case .playlist:
            searchField.placeholderString = "Type to filter…"
            goToCurrentButton.isHidden = false
        case .radio:
            searchField.placeholderString = "Search all SHOUTcast…"
            goToCurrentButton.isHidden = true
        }
    }

    /// Recompute the list for the current mode + query.
    private func refreshResults() {
        radioDebounce?.invalidate()
        radioSearchTask?.cancel()
        switch mode {
        case .playlist:
            matches = JumpFilter.filter(query: searchField.stringValue, candidates: candidates)
            tableView.reloadData()
            statusLabel.stringValue = "\(matches.count) of \(candidates.count) tracks"
            if !matches.isEmpty { select(0) }
        case .radio:
            let q = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            radioStations = []
            tableView.reloadData()
            statusLabel.stringValue = q.isEmpty ? "Type to search SHOUTcast" : "Searching…"
            if !q.isEmpty { scheduleRadioSearch(q) }
        }
    }

    /// Debounce keystrokes so we don't hit the directory on every character.
    private func scheduleRadioSearch(_ query: String) {
        radioDebounce?.invalidate()
        radioDebounce = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.startRadioSearch(query)
        }
    }

    private func startRadioSearch(_ query: String) {
        radioSearchTask?.cancel()
        radioSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let results = try await self.radioManager?.searchStations(query) ?? []
                if Task.isCancelled { return }
                self.radioStations = results
                self.tableView.reloadData()
                self.statusLabel.stringValue = results.isEmpty
                    ? "No stations for \u{201C}\(query)\u{201D}"
                    : "\(results.count) stations"
                if !results.isEmpty { self.select(0) }
            } catch {
                if Task.isCancelled { return }
                self.radioStations = []
                self.tableView.reloadData()
                self.statusLabel.stringValue = "Search failed"
            }
        }
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        refreshResults()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: +1); return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1); return true
        case #selector(NSResponder.moveToBeginningOfDocument(_:)),
             #selector(NSResponder.scrollPageUp(_:)):
            select(0); return true
        case #selector(NSResponder.moveToEndOfDocument(_:)),
             #selector(NSResponder.scrollPageDown(_:)):
            select(rowCount - 1); return true
        case #selector(NSResponder.insertNewline(_:)):
            playSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            close(); return true
        case #selector(NSResponder.insertTab(_:)),
             #selector(NSResponder.insertBacktab(_:)):
            return true   // eat Tab so focus can't escape the search field
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard rowCount > 0 else { return }
        let current = tableView.selectedRow
        let proposed = current < 0 ? (delta > 0 ? 0 : rowCount - 1) : current + delta
        select(max(0, min(rowCount - 1, proposed)))
    }

    private func select(_ row: Int) {
        guard row >= 0, row < rowCount else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "." {
            close()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { rowCount }

    func tableView(_ tv: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = tv.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let v = NSTableCellView()
            v.identifier = identifier
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingTail
            tf.font = NSFont.systemFont(ofSize: 12)
            v.addSubview(tf)
            v.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            ])
            return v
        }()

        if mode == .radio {
            guard row < radioStations.count else { return cell }
            let s = radioStations[row]
            var meta: [String] = []
            if s.bitrate > 0 { meta.append("\(s.bitrate)k") }
            meta.append("\(s.listenersDisplay) listeners")
            cell.textField?.stringValue = "\(s.name)   —   \(meta.joined(separator: " · "))"
        } else {
            guard row < matches.count else { return cell }
            let m = matches[row]
            if let c = candidates.first(where: { $0.index == m.index }) {
                cell.textField?.stringValue = c.displayTitle
            }
        }
        return cell
    }

    // MARK: - Actions

    @objc private func handleDoubleClick() { playSelected() }

    @objc private func scrollToCurrent() {
        guard mode == .playlist,
              let curIdx = jumpDelegate?.currentTrackIndex,
              let row = matches.firstIndex(where: { $0.index == curIdx }) else { return }
        select(row)
    }

    private func playSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < rowCount else { return }
        if mode == .radio {
            let station = radioStations[row]
            if let rm = radioManager { Task { @MainActor in await rm.playStation(station) } }
            close()
            return
        }
        playPlaylistRow(row)
    }

    private func playPlaylistRow(_ row: Int) {
        let staleIndex = matches[row].index
        guard let stale = candidates.first(where: { $0.index == staleIndex }) else { return }
        // The panel is non-modal: the playlist may have been reordered or edited
        // while it was open, so the snapshot index can point at a different track
        // now. Re-resolve against the live playlist.
        let fresh = jumpDelegate?.jumpCandidates ?? []
        let target: Int?
        if staleIndex < fresh.count,
           fresh[staleIndex].displayTitle == stale.displayTitle,
           fresh[staleIndex].filename == stale.filename {
            target = staleIndex
        } else {
            target = fresh.first(where: {
                $0.displayTitle == stale.displayTitle && $0.filename == stale.filename
            })?.index
        }
        if let target {
            jumpDelegate?.playTrack(atPlaylistIndex: target)
        }
        close()
    }
}
