// SPDX-License-Identifier: GPL-3.0-or-later
import ATCCore
import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void

    var body: some View {
        let panel = model.panel
        VStack(alignment: .leading, spacing: 0) {
            if let notice = panel.notice {
                Text(notice)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        lamps(panel)
                        pending(panel)
                        status(panel)
                    }
                    .padding(14)
                }
            }
            Divider()
            footer
        }
        .frame(width: 420, height: 520)
    }

    // MARK: Lamps

    @ViewBuilder private func lamps(_ panel: PanelContent) -> some View {
        if panel.sections.isEmpty {
            Text("켜진 LAMP 없음").foregroundStyle(.secondary)
        }
        ForEach(panel.sections) { section in
            VStack(alignment: .leading, spacing: 4) {
                header("\(section.title) · \(section.rows.count)", color: color(section.level))
                ForEach(section.rows) { row in
                    Button { open(row.url) } label: { lamp(row) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func lamp(_ row: LampRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color(row.level)).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.text).font(.callout).lineLimit(3).multilineTextAlignment(.leading)
                if let place = row.place { Text(place).font(.caption).foregroundStyle(.secondary) }
                if let next = row.next { Text("→ \(next)").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pending

    @ViewBuilder private func pending(_ panel: PanelContent) -> some View {
        if !panel.pending.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                header("PENDING", color: .secondary)
                ForEach(panel.pending) { row in
                    Button { open(row.url) } label: {
                        HStack {
                            Text(row.title)
                            Spacer()
                            Text("\(row.count)").monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: RTS, FUEL, working

    @ViewBuilder private func status(_ panel: PanelContent) -> some View {
        if panel.hasSummary {
            if let rts = panel.rts {
                VStack(alignment: .leading, spacing: 4) {
                    header("RTS", color: .secondary)
                    Text(rts).font(.callout).monospacedDigit()
                }
            }
            if !panel.fuel.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    header("FUEL" + (panel.fuelLabel.map { " · \($0)" } ?? ""), color: .secondary)
                    ForEach(panel.fuel) { w in
                        HStack {
                            Text(w.name)
                            Spacer()
                            Text(w.used).monospacedDigit()
                            if let resets = w.resets {
                                Text("reset \(resets)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                header("WORKING", color: .secondary)
                Text("AIRCRAFT \(panel.workingAircraft) · 관제 세션 \(panel.workingControl)").font(.callout)
                if !panel.needsYou.isEmpty {
                    Text("NEEDS YOU: " + panel.needsYou.joined(separator: ", "))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Open atc") { open(ATCLink.url(base: model.baseURL, link: nil)) }
            Button("Refresh") { model.refresh() }
            Spacer()
            Button("Settings…") { openSettings() }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(10)
    }

    // MARK: Helpers

    private func header(_ text: String, color: Color) -> some View {
        Text(text).font(.caption.weight(.bold)).foregroundStyle(color)
    }

    private func color(_ level: AlertLevel) -> Color {
        switch level {
        case .warning: return .red
        case .caution: return .orange
        case .advisory: return .secondary
        }
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
