// SPDX-License-Identifier: GPL-3.0-or-later
import ATCCore
import Foundation

/// View state of the popover, kept in an ObservableObject (SwiftUI state macros need Xcode; see Tools/test-linux.sh).
/// The fold rules are in ATCCore (`LampExpansion`); this only remembers them.
@MainActor
final class PopoverState: ObservableObject {
    static let expansionKey = "lampExpansion"

    @Published private(set) var expansion: LampExpansion
    @Published var hoveredRow: String?
    /// Rows whose `next` line is pinned open with the chevron. Not remembered.
    @Published private(set) var openRows: Set<String> = []

    init() {
        expansion = LampExpansion(stored: UserDefaults.standard.stringArray(forKey: Self.expansionKey))
    }

    func toggle(_ level: AlertLevel) {
        var next = expansion
        next.toggle(level)
        expansion = next
        UserDefaults.standard.set(next.stored, forKey: Self.expansionKey)
    }

    func toggleRow(_ id: String) {
        if openRows.contains(id) { openRows.remove(id) } else { openRows.insert(id) }
    }
}
