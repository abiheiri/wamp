import Cocoa

/// Delegate for ShoutcastBrowserWindow — implemented by AppDelegate.
protocol ShoutcastBrowserDelegate: AnyObject {
    /// Play the stream at the given URL.
    func playStream(url: URL, title: String)
}

/// Floating window that browses SHOUTcast stations by genre or search.
final class ShoutcastBrowserWindow: NSPanel, NSTableViewDataSource, NSTableViewDelegate {

    // MARK: - Constants

    private static let windowWidth: CGFloat = 550
    private static let windowHeight: CGFloat = 400

    private static let popularGenres = [
        "Alternative", "Blues", "Classical", "Country", "Dance",
        "Electronic", "Folk", "Hip Hop", "Indie", "Jazz",
        "Latin", "Metal", "Pop", "R&B", "Reggae",
        "Rock", "Soul", "Talk", "Top 40", "World"
    ]

    // MARK: - Delegate

    weak var browserDelegate: ShoutcastBrowserDelegate?

    // MARK: - State

    private let client = ShoutcastDirectoryClient()
    private var stations: [ShoutcastStation] = []
    private var isSearching = false

    // MARK: - UI Elements

    private let searchField = NSSearchField()
    private let genrePopup = NSPopUpButton()
    private let loadButton = NSButton(title: "Load", target: nil, action: nil)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let playButton = NSButton(title: "Play", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let spinner = NSProgressIndicator()

    // MARK: - Columns

    private enum ColumnID: String {
        case name = "name"
        case bitrate = "bitrate"
        case listeners = "listeners"
    }

    // MARK: - Init

    init() {
        let rect = NSRect(x: 0, y: 0, width: Self.windowWidth, height: Self.windowHeight)
        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "SHOUTcast Radio"
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 350, height: 250)
        setupContent()
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Setup

    private func setupContent() {
        guard let content = contentView else { return }

        // Search field
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search stations..."
        searchField.target = self
        searchField.action = #selector(searchAction)
        content.addSubview(searchField)

        // Genre popup
        genrePopup.translatesAutoresizingMaskIntoConstraints = false
        genrePopup.addItems(withTitles: Self.popularGenres)
        genrePopup.selectItem(at: 10) // Jazz
        content.addSubview(genrePopup)

        // Load button
        loadButton.translatesAutoresizingMaskIntoConstraints = false
        loadButton.bezelStyle = .rounded
        loadButton.target = self
        loadButton.action = #selector(loadGenre)
        content.addSubview(loadButton)

        // Spinner
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        spinner.controlSize = .small
        content.addSubview(spinner)

        // Table
        tableView.translatesAutoresizingMaskIntoConstraints = false
        setupTableView()
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        content.addSubview(scrollView)

        // Status
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Choose a genre and click Load"
        content.addSubview(statusLabel)

        // Buttons
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.bezelStyle = .rounded
        playButton.target = self
        playButton.action = #selector(playSelected)
        playButton.isEnabled = false
        content.addSubview(playButton)

        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.bezelStyle = .rounded
        stopButton.target = self
        stopButton.action = #selector(stopPlayback)
        content.addSubview(stopButton)

        // Layout
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            genrePopup.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            genrePopup.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),

            loadButton.centerYAnchor.constraint(equalTo: genrePopup.centerYAnchor),
            loadButton.leadingAnchor.constraint(equalTo: genrePopup.trailingAnchor, constant: 8),

            spinner.centerYAnchor.constraint(equalTo: genrePopup.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: loadButton.trailingAnchor, constant: 8),

            scrollView.topAnchor.constraint(equalTo: genrePopup.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            playButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            playButton.trailingAnchor.constraint(equalTo: stopButton.leadingAnchor, constant: -8),

            stopButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            stopButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
        ])
    }

    private func setupTableView() {
        // Name column
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(ColumnID.name.rawValue))
        nameCol.title = "Name"
        nameCol.width = 330
        nameCol.minWidth = 150
        nameCol.resizingMask = .autoresizingMask
        tableView.addTableColumn(nameCol)

        // Bitrate column
        let brCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(ColumnID.bitrate.rawValue))
        brCol.title = "BR"
        brCol.width = 55
        brCol.minWidth = 40
        brCol.resizingMask = .autoresizingMask
        tableView.addTableColumn(brCol)

        // Listeners column
        let listCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(ColumnID.listeners.rawValue))
        listCol.title = "Listeners"
        listCol.width = 70
        listCol.minWidth = 50
        listCol.resizingMask = .autoresizingMask
        tableView.addTableColumn(listCol)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 20
        tableView.usesAutomaticRowHeights = false
        tableView.doubleAction = #selector(playSelected)
        tableView.target = self
        if #available(macOS 11.0, *) {
            tableView.style = .plain
        }
    }

    // MARK: - Present

    func present(over parent: NSWindow?) {
        if let parent {
            let parentFrame = parent.frame
            let x = parentFrame.midX - frame.width / 2
            let y = parentFrame.midY - frame.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            center()
        }
        makeKeyAndOrderFront(nil)
    }

    // MARK: - Actions

    @objc private func searchAction() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        searchStations(query: query)
    }

    @objc private func loadGenre() {
        let genre = genrePopup.titleOfSelectedItem ?? "Jazz"
        browseGenre(genre)
    }

    @objc private func playSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < stations.count else { return }
        let station = stations[row]
        resolveAndPlay(station)
    }

    @objc private func stopPlayback() {
        // Post notification to stop — AppDelegate will handle
        NotificationCenter.default.post(name: .shoutcastStopStream, object: nil)
    }

    // MARK: - Data Loading

    private func browseGenre(_ genre: String) {
        guard !isSearching else { return }
        isSearching = true
        spinner.startAnimation(nil)
        statusLabel.stringValue = "Loading \(genre)..."
        playButton.isEnabled = false

        Task { @MainActor in
            do {
                let results = try await client.browseByGenre(genre)
                stations = results
                tableView.reloadData()
                statusLabel.stringValue = "\(results.count) stations in \(genre)"
            } catch {
                stations = []
                tableView.reloadData()
                statusLabel.stringValue = "Failed to load: \(error.localizedDescription)"
            }
            isSearching = false
            spinner.stopAnimation(nil)
        }
    }

    private func searchStations(query: String) {
        guard !isSearching else { return }
        isSearching = true
        spinner.startAnimation(nil)
        statusLabel.stringValue = "Searching..."
        playButton.isEnabled = false

        Task { @MainActor in
            do {
                let results = try await client.search(query)
                stations = results
                tableView.reloadData()
                statusLabel.stringValue = "\(results.count) results for \"\(query)\""
            } catch {
                stations = []
                tableView.reloadData()
                statusLabel.stringValue = "Search failed"
            }
            isSearching = false
            spinner.stopAnimation(nil)
        }
    }

    private func resolveAndPlay(_ station: ShoutcastStation) {
        guard !isSearching else { return }
        isSearching = true
        spinner.startAnimation(nil)
        statusLabel.stringValue = "Connecting to \(station.name)..."

        Task { @MainActor in
            do {
                let url = try await client.getStreamURL(for: station.id)
                isSearching = false
                spinner.stopAnimation(nil)
                statusLabel.stringValue = "Playing: \(station.name)"
                playButton.isEnabled = true
                browserDelegate?.playStream(url: url, title: station.name)
            } catch {
                isSearching = false
                spinner.stopAnimation(nil)
                statusLabel.stringValue = "Failed to resolve stream URL"
            }
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        stations.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < stations.count, let columnID = tableColumn?.identifier.rawValue else { return nil }
        let station = stations[row]

        let cellID = NSUserInterfaceItemIdentifier("cell_\(columnID)")
        let view: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
            view = existing
        } else {
            let tf = NSTextField()
            tf.isEditable = false
            tf.isBordered = false
            tf.drawsBackground = false
            tf.font = NSFont.systemFont(ofSize: 12)
            view = NSTableCellView()
            view.identifier = cellID
            view.textField = tf
            view.addSubview(tf)
            tf.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
                tf.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                tf.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4)
            ])
        }

        switch ColumnID(rawValue: columnID) {
        case .name:
            view.textField?.stringValue = station.name
        case .bitrate:
            view.textField?.stringValue = station.bitrate > 0 ? "\(station.bitrate) kbps" : ""
        case .listeners:
            view.textField?.stringValue = station.listeners > 0 ? "\(station.listeners)" : ""
        default:
            break
        }

        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        playButton.isEnabled = tableView.selectedRow >= 0
    }
}

// MARK: - Notification

extension Notification.Name {
    static let shoutcastStopStream = Notification.Name("shoutcastStopStream")
}
