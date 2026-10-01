// SPDX-License-Identifier: Apache-2.0
import AppKit
import ATCCore
import Combine

/// The Work window (ATC-247, design 11.3): one small AppKit list of open PRs. No editor, no detail pane, no search.
/// A row click opens the PR in the default browser; "Decide in atc ↗" opens the atc window at STRIPS. The rows,
/// labels and links come from ATCCore (`WorkPanel`, `LinkRoute.workLink`); titles are shown as plain text.
@MainActor
final class WorkWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let frameName = "work"
    private static let cellID = NSUserInterfaceItemIdentifier("WorkRowCell")

    private let work: WorkModel
    private let model: AppModel
    /// Called before the window comes forward (the popover closes).
    var onWillShow: (() -> Void)?
    /// True when the atc window is open, so closing this one leaves the app a regular app.
    var isAtcOpen: () -> Bool = { false }

    private var window: NSWindow?
    private var table = NSTableView()
    private let headerLabel = NSTextField(labelWithString: "")
    private var filterControl: NSSegmentedControl?
    private var rows: [WorkRow] = []
    private var watch: AnyCancellable?

    init(work: WorkModel, model: AppModel) {
        self.work = work
        self.model = model
    }

    var isOpen: Bool { window != nil }

    // MARK: Showing

    func show() {
        onWillShow?()
        if window == nil { build() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        work.setViewing("window", true)
        reload()
    }

    private func build() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        win.title = "Work"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.minSize = NSSize(width: 480, height: 280)

        let filter = NSSegmentedControl(labels: ["All", "Review requested"], trackingMode: .selectOne, target: self, action: #selector(filterChanged))
        filter.selectedSegment = work.filter == .all ? 0 : 1
        filterControl = filter
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshClicked))
        refresh.bezelStyle = .rounded
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [filter, spacer, refresh])
        bar.orientation = .horizontal

        headerLabel.font = .systemFont(ofSize: 11)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.lineBreakMode = .byTruncatingTail

        table = NSTableView()  // a fresh table per window: no stale column after a reopen
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pr"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 54
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        let content = NSView()
        for v in [bar, headerLabel, scroll] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            headerLabel.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            headerLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            headerLabel.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        win.contentView = content
        win.setFrameAutosaveName(Self.frameName)
        if !win.setFrameUsingName(Self.frameName) { win.center() }
        window = win

        // objectWillChange fires before the change: hop to the next turn to read the new values.
        watch = work.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.reload() } }
        }
    }

    private func reload() {
        guard window != nil else { return }
        rows = work.rows
        headerLabel.stringValue = work.signedIn ? work.header : "GitHub에 로그인하세요 (Settings)"
        if !work.signedIn { rows = [] }
        table.reloadData()
    }

    // MARK: Actions

    @objc private func filterChanged() {
        work.filter = filterControl?.selectedSegment == 1 ? .reviewRequested : .all
        reload()
    }

    @objc private func refreshClicked() { work.refreshNow() }

    /// A click on the row (not on its button): the PR page in the default browser.
    @objc private func rowClicked() {
        let r = table.clickedRow
        guard rows.indices.contains(r), let url = rows[r].url else { return }
        NSWorkspace.shared.open(url)
    }

    private func decide() {
        LinkOpener.open(ATCLink.url(base: model.baseURL, link: "#" + WorkPanel.atcFragment))
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let cell = (tableView.makeView(withIdentifier: Self.cellID, owner: self) as? WorkRowCell) ?? WorkRowCell(frame: .zero)
        cell.identifier = Self.cellID
        cell.configure(rows[row])
        cell.onDecide = { [weak self] in self?.decide() }
        return cell
    }

    // MARK: Closing

    func windowWillClose(_ notification: Notification) {
        work.setViewing("window", false)
        watch = nil
        let closing = window
        window = nil
        filterControl = nil
        closing?.delegate = nil
        closing?.contentView = nil
        table.dataSource = nil
        table.delegate = nil
        // Keep the window object alive until AppKit is done with it.
        DispatchQueue.main.async { _ = closing }
        if !isAtcOpen() { NSApp.setActivationPolicy(.accessory) }
    }
}

/// One PR row: title, a detail line with the CI and review words, and the "Decide in atc ↗" button.
/// Everything shown is plain text from `WorkRow`.
final class WorkRowCell: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let ciField = NSTextField(labelWithString: "")
    private let reviewField = NSTextField(labelWithString: "")
    private let decideButton = NSButton(title: "Decide in atc ↗", target: nil, action: nil)
    var onDecide: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { nil }

    private func setup() {
        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        detailField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailField.textColor = .secondaryLabelColor
        ciField.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        reviewField.font = .systemFont(ofSize: 11, weight: .semibold)
        reviewField.textColor = .controlAccentColor
        decideButton.bezelStyle = .inline
        decideButton.target = self
        decideButton.action = #selector(decideClicked)
        decideButton.setContentHuggingPriority(.required, for: .horizontal)
        decideButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let second = NSStackView(views: [detailField, ciField, reviewField])
        second.orientation = .horizontal
        second.spacing = 8
        let text = NSStackView(views: [titleField, second])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let row = NSStackView(views: [text, decideButton])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(_ row: WorkRow) {
        titleField.stringValue = row.title
        titleField.toolTip = row.title
        detailField.stringValue = row.detail + (row.isDraft ? " · draft" : "")
        ciField.stringValue = row.ciLabel
        switch row.ci {
        case .failing: ciField.textColor = .systemRed
        case .pending: ciField.textColor = .systemOrange
        case .passing: ciField.textColor = .systemGreen
        case .none: ciField.textColor = .secondaryLabelColor
        }
        reviewField.stringValue = row.reviewLabel ?? ""
        reviewField.isHidden = row.reviewLabel == nil
        setAccessibilityLabel([row.title, row.detail, row.ciLabel, row.reviewLabel].compactMap { $0 }.joined(separator: ", "))
    }

    @objc private func decideClicked() { onDecide?() }
}
