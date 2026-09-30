// SPDX-License-Identifier: GPL-3.0-or-later
import ATCCore
import AppKit
import SwiftUI

/// Layout only: order, folding, chips, age and height come from ATCCore (`PanelContent`, `PanelLayout`).
/// Server text is shown as is; it is cut with `lineLimit` and the full text is the tooltip.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: PopoverState
    var openSettings: () -> Void

    var body: some View {
        // Re-evaluated every minute so the ages keep moving without a feed change.
        TimelineView(.everyMinute) { context in
            content(PanelContent(model.feed, base: model.baseURL, now: context.date))
        }
    }

    private func content(_ panel: PanelContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let notice = panel.notice {
                Text(notice)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                if panel.notice == PanelContent.unreachableNotice { ForwardLineView(forward: model.forward) }
                Spacer(minLength: 0)
            } else {
                strip(panel)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        lamps(panel)
                    }
                    .padding(12)
                }
            }
            Divider()
            footer
        }
        .frame(
            width: PanelLayout.width,
            height: PanelLayout.height(for: panel, expansion: state.expansion, radioLine: model.radioPrefs.on, dutyLine: model.duty != nil))
    }

    // MARK: Fixed strip

    @ViewBuilder private func strip(_ panel: PanelContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(panel.tiles) { tile in
                    tileView(tile)
                }
            }
            if !panel.pending.isEmpty || !panel.needsYouChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(panel.pending) { row in
                            Button { LinkOpener.open(row.url) } label: {
                                Text("\(row.title) \(row.count)").font(.caption.monospaced())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Color.primary.opacity(0.10)))
                            }
                            .buttonStyle(.plain)
                            .help("\(row.title) — atc에서 열기")
                        }
                        if !panel.needsYouChips.isEmpty {
                            // Own style (accent colour), so it is never mistaken for a CAUTION.
                            Text("NEEDS YOU").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                            ForEach(panel.needsYouChips) { chip in
                                Button { LinkOpener.open(chip.url) } label: {
                                    Text(chip.name).font(.caption.monospaced())
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                                        .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .help("\(chip.name) — atc에서 열기")
                            }
                        }
                    }
                }
            }
            ForEach(panel.fuel) { w in
                HStack(spacing: 8) {
                    Text(w.name).font(.caption.monospaced()).frame(width: 34, alignment: .leading)
                    fuelBar(w.fraction)
                    Text(w.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .trailing)
                }
            }
            Text(panel.statusLine).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                .help(panel.statusLine)
            if let lamp = model.duty { dutyRow(lamp) }
            if let hint = RadioHint(model.radio) {
                HStack(spacing: 6) {
                    Text(hint.title).font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                    Text(hint.detail).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        .help(hint.detail)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
    }

    /// DUTY and its state dot; a click opens the atc window at `#duty`. No sound, no notification.
    private func dutyRow(_ lamp: DutyLamp) -> some View {
        Button { LinkOpener.open(ATCLink.url(base: model.baseURL, link: "#" + DutyLamp.fragment)) } label: {
            HStack(spacing: 6) {
                Text("DUTY").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                Circle().fill(dutyColor(lamp.dot)).frame(width: 8, height: 8)
                Spacer(minLength: 0)
                Text("↗").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(lamp.tooltip)
        .accessibilityLabel(lamp.tooltip + ", " + lamp.dot.rawValue)
        .accessibilityHint("atc에서 엽니다")
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

    private func fuelBar(_ fraction: Double?) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Color.accentColor).frame(width: geo.size.width * (fraction ?? 0))
            }
        }
        .frame(height: 6)
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
                        Text(row.text).font(.callout).lineLimit(2).multilineTextAlignment(.leading)
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

    private var footer: some View {
        HStack(spacing: 10) {
            Button { LinkOpener.open(ATCLink.url(base: model.baseURL, link: nil)) } label: { Text("Open atc ↗") }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            Spacer()
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh (⌘R)")
                .accessibilityLabel("Refresh")
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
            Menu {
                Button("Quit ANNUNCIATOR") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More")
        }
        .padding(10)
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
