// SPDX-License-Identifier: Apache-2.0
import ATCCore
import AppKit
import SwiftUI

/// Layout only: order, folding, chips, age and height come from ATCCore (`PanelContent`, `PanelLayout`).
/// Server text is shown as is; it is cut with `lineLimit` and the full text is the tooltip.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: PopoverState
    @ObservedObject var work: WorkModel
    var openSettings: () -> Void
    var openWork: () -> Void

    var body: some View {
        // Re-evaluated every minute so the ages keep moving without a feed change.
        TimelineView(.everyMinute) { context in
            content(PanelContent(model.feed, base: model.baseURL, now: context.date), now: context.date)
        }
    }

    private func content(_ panel: PanelContent, now: Date) -> some View {
        let status = StatusRows(duty: model.duty, work: work.line(now: now), linear: work.linearLine(now: now), radio: RadioHint(model.radio))
        return VStack(alignment: .leading, spacing: 0) {
            if let notice = panel.notice {
                Text(notice)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                if panel.notice == PanelContent.unreachableNotice { ForwardLineView(forward: model.forward) }
                Spacer(minLength: 0)
            } else {
                summaryHeader(panel)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        lamps(panel)
                        if !panel.groups.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(panel.groups) { groupRow($0) }
                            }
                        }
                    }
                    .padding(12)
                }
                statusGroup(status)
                if let fuel = panel.fuelBar { fuelRow(fuel) }
            }
            Divider()
            footer
        }
        .frame(
            width: PanelLayout.width,
            height: PanelLayout.height(
                for: panel, expansion: state.expansion, status: status,
                openGroups: state.openGroups, statusOpened: state.statusOpened))
    }

    // MARK: Header

    /// Tiles while something is lit; otherwise one calm line.
    @ViewBuilder private func summaryHeader(_ panel: PanelContent) -> some View {
        if panel.allNormal {
            Text(PanelContent.allNormalText)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)
        } else {
            HStack(spacing: 8) {
                ForEach(panel.tiles) { tileView($0) }
            }
            .padding(12)
        }
    }

    // MARK: Header rows (PENDING, NEEDS YOU, RTS, working)

    private func groupRow(_ group: InfoGroup) -> some View {
        let open = state.openGroups.contains(group.id)
        let tint: Color = group.isNeedsYou ? .accentColor : .secondary
        return VStack(alignment: .leading, spacing: 2) {
            if group.isExpandable {
                Button { state.toggleGroup(group.id) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: open ? "chevron.down" : "chevron.right").font(.caption2)
                        Text(group.header).font(.caption.monospaced().weight(group.isNeedsYou ? .bold : .regular)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(tint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(open ? "접기" : "펼치기")
            } else {
                Text(group.header).font(.caption.monospaced()).foregroundStyle(tint).lineLimit(1)
                    .help(group.header)
                    .padding(.leading, 14)
            }
            ForEach(group.visibleItems(expanded: open)) { item in
                Button { LinkOpener.open(item.url) } label: {
                    Text(item.text).font(.caption.monospaced()).lineLimit(1)
                        .foregroundStyle(tint)
                        .padding(.leading, 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(item.text) — atc에서 열기")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 1)
    }

    // MARK: Status row group (DUTY, GitHub, RADIO)

    @ViewBuilder private func statusGroup(_ status: StatusRows) -> some View {
        if !status.rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if status.isFolded {
                    Button { state.toggleStatus() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: state.statusOpened ? "chevron.down" : "chevron.right").font(.caption2)
                            Text(status.summary).font(.caption.monospaced()).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(state.statusOpened ? "접기" : "펼치기")
                }
                if !status.isFolded || state.statusOpened {
                    ForEach(status.rows) { statusRow($0) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    /// One line. DUTY and GitHub click through (atc window `#duty`, Work window); RADIO is text only. No sound, no notification.
    @ViewBuilder private func statusRow(_ row: StatusRow) -> some View {
        let line = HStack(spacing: 6) {
            if let dot = row.dot { Circle().fill(dutyColor(dot)).frame(width: 8, height: 8) }
            Text(row.text).font(.caption.monospaced()).lineLimit(1)
                .foregroundStyle(row.attention || row.isNotice ? Color.orange : Color.secondary)
            Spacer(minLength: 0)
            if row.kind != .radio { Text("↗").font(.caption).foregroundStyle(.secondary) }
        }
        .contentShape(Rectangle())
        switch row.kind {
        case .duty:
            Button { LinkOpener.open(ATCLink.url(base: model.baseURL, link: "#" + DutyLamp.fragment)) } label: { line }
                .buttonStyle(.plain)
                .help(row.text)
                .accessibilityLabel(row.text + (row.dot.map { ", " + $0.rawValue } ?? ""))
                .accessibilityHint("atc에서 엽니다")
        case .work, .linear:
            // The Work window opens on the list of the line that was clicked.
            Button { work.source = row.kind == .linear ? .linear : .github; openWork() } label: { line }
                .buttonStyle(.plain)
                .help(row.text)
                .accessibilityHint("Work 창을 엽니다")
        case .radio:
            line.help(row.text).accessibilityElement(children: .combine)
        }
    }

    private func dutyColor(_ dot: DutyDot) -> Color {
        switch dot {
        case .green: return .green
        case .amber: return .orange
        case .red: return .red
        case .grey: return .gray
        }
    }

    private func tileView(_ tile: AnnunciatorTile) -> some View {
        let tint = color(tile.level)
        return VStack(spacing: 2) {
            Text(tile.label).font(.caption2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(tile.count)").font(.title2.monospaced().weight(.bold))
        }
        .foregroundStyle(tile.isLit ? tint : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(tile.isLit ? tint.opacity(0.18) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(tile.isLit ? tint : Color.secondary.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.label) \(tile.count)")
    }

    /// One thin bar with the number, at the bottom.
    private func fuelRow(_ w: FuelRow) -> some View {
        HStack(spacing: 8) {
            Text(w.name).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            fuelBar(w.fraction)
            Text(w.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FUEL \(w.name) \(w.used)")
    }

    private func fuelBar(_ fraction: Double?) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Color.accentColor).frame(width: geo.size.width * (fraction ?? 0))
            }
        }
        .frame(height: 4)
    }

    // MARK: Lamps

    @ViewBuilder private func lamps(_ panel: PanelContent) -> some View {
        if panel.sections.isEmpty {
            Text("켜진 LAMP 없음").foregroundStyle(.secondary)
        }
        ForEach(panel.sections) { section in
            let expanded = state.expansion.isExpanded(section.level)
            VStack(alignment: .leading, spacing: 2) {
                sectionHeader(section, expanded: expanded)
                ForEach(section.visibleRows(expanded: expanded)) { row in
                    lampRow(row)
                }
                if let label = section.toggleLabel(expanded: expanded) {
                    Button { state.toggle(section.level) } label: {
                        Text(label).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }
            }
        }
    }

    @ViewBuilder private func sectionHeader(_ section: LampSection, expanded: Bool) -> some View {
        let label = Text(section.header).font(.caption.weight(.bold)).foregroundStyle(color(section.level))
        if LampFold.isCollapsible(section.level) {
            Button { state.toggle(section.level) } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2)
                    label
                }
                .foregroundStyle(color(section.level))
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "접기" : "펼치기")
        } else {
            label
        }
    }

    private func lampRow(_ row: LampRow) -> some View {
        let hovered = state.hoveredRow == row.id
        let showNext = row.next != nil && (hovered || state.openRows.contains(row.id))
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { LinkOpener.open(row.url) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.chip).font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(RoundedRectangle(cornerRadius: 3).fill(color(row.level)))
                        if let place = row.place {
                            Text(place).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text(row.text).font(.callout).lineLimit(1).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if hovered { Text("↗").foregroundStyle(.secondary) }
                        if let age = row.age { Text(age).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(row.text)
                .accessibilityLabel(accessibilityLabel(row))
                .accessibilityHint("atc에서 엽니다")
                if row.next != nil {
                    Button { state.toggleRow(row.id) } label: {
                        Image(systemName: state.openRows.contains(row.id) ? "chevron.up" : "chevron.down").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("다음 단계 보기")
                    .accessibilityLabel("다음 단계")
                }
            }
            if showNext, let next = row.next {
                Text("→ \(next)").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    .padding(.leading, 22)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(hovered ? Color.primary.opacity(0.08) : Color.clear))
        .onHover { inside in
            if inside {
                state.hoveredRow = row.id
                NSCursor.pointingHand.push()
            } else {
                if state.hoveredRow == row.id { state.hoveredRow = nil }
                NSCursor.pop()
            }
        }
    }

    private func accessibilityLabel(_ row: LampRow) -> String {
        [row.level.rawValue.uppercased(), row.place, row.text, row.age.map { "\($0) 전" }, row.next.map { "다음: \($0)" }]
            .compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: Footer

    /// Open atc and the gear only. Refresh (⌘R) and Quit (⌘Q) live in the title's right-click menu;
    /// their shortcuts also work here while the popover is open, through the hidden buttons below.
    private var footer: some View {
        HStack(spacing: 10) {
            Button { LinkOpener.open(ATCLink.url(base: model.baseURL, link: nil)) } label: { Text("Open atc ↗") }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            Spacer()
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
        }
        .padding(10)
        .background(shortcuts)
    }

    private var shortcuts: some View {
        ZStack {
            Button("Refresh") { model.refresh() }.keyboardShortcut("r", modifiers: .command)
            Button("Quit ANNUNCIATOR") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: Helpers

    /// The two lamp colours; ADVISORY is grey.
    private func color(_ level: AlertLevel) -> Color {
        switch level {
        case .warning: return .red
        case .caution: return .orange
        case .advisory: return .gray
        }
    }
}


/// While atc is unreachable and a host is set: the forward's state and its one matching button (ATC-204).
/// Its own view, so it follows `ForwardMonitor` (a separate ObservableObject).
struct ForwardLineView: View {
    @ObservedObject var forward: ForwardMonitor

    var body: some View {
        if let state = forward.state {
            VStack(alignment: .leading, spacing: 6) {
                Text(state.line).font(.caption.monospaced()).foregroundStyle(.secondary)
                if !state.hint.isEmpty {
                    Text(state.hint).font(.caption).foregroundStyle(.secondary)
                }
                if let title = state.action.title {
                    Button(title) { forward.perform(state.action) }.disabled(forward.busy)
                }
                if !forward.error.isEmpty {
                    Text(forward.error).font(.caption).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
        }
    }
}
