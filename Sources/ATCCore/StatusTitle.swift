// SPDX-License-Identifier: GPL-3.0-or-later

/// Menu bar title text. Hello-world stand-in for the real title state.
public enum StatusTitle {
    public static let glyph = "✈"

    /// "✈" alone, or "✈ 3" when `litCount` is positive.
    public static func text(litCount: Int = 0) -> String {
        litCount > 0 ? "\(glyph) \(litCount)" : glyph
    }
}
