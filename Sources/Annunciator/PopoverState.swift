// SPDX-License-Identifier: Apache-2.0
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

    /// Header rows (`InfoGroup` ids) and the status group that the user opened. Not remembered.
    @Published private(set) var openGroups: Set<String> = []
    @Published private(set) var statusOpened = false

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

    func toggleGroup(_ id: String) {
        if openGroups.contains(id) { openGroups.remove(id) } else { openGroups.insert(id) }
    }

    func toggleStatus() { statusOpened.toggle() }
}
