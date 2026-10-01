// SPDX-License-Identifier: Apache-2.0
import AppKit
import ATCCore

/// Draws the menu bar item (ATC-222). Which glyph and badge, and the count, come from `MenuTitle` in ATCCore.
/// Idle is a template image, so it follows the light or dark menu bar; badges are coloured and differ in shape.
@MainActor
enum TitleImages {
    private static let pointSize: CGFloat = 13

    /// The aircraft as a template (idle, caution; warning uses a heavier weight, so the glyph reads filled).
    static func aircraft(_ glyph: MenuTitle.Glyph) -> NSImage? {
        switch glyph {
        case .unreachable: return slashed()
        case .idle, .caution: return plane(weight: .regular)
        case .warning: return plane(weight: .black)
        }
    }

    private static func plane(weight: NSFont.Weight) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    /// Grey aircraft with a slash: the meaning of the old grey light.
    private static func slashed() -> NSImage? {
        let grey = NSColor.systemGray
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [grey]))
        guard let base = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            grey.setStroke()
            let slash = NSBezierPath()
            slash.lineWidth = 1.6
            slash.lineCapStyle = .round
            slash.move(to: NSPoint(x: rect.minX + 1, y: rect.maxY - 1))
            slash.line(to: NSPoint(x: rect.maxX - 1, y: rect.minY + 1))
            slash.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The text after the glyph: badge (amber dot or red triangle) and count, FUEL, then the blue NEEDS YOU dot.
    static func attributedTitle(_ title: MenuTitle) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small) + 1, weight: .medium)
        let out = NSMutableAttributedString()
        switch title.glyph {
        case .caution: out.append(attachment("circle.fill", .systemOrange, size: 8))
        case .warning: out.append(attachment("exclamationmark.triangle.fill", .systemRed, size: 11))
        case .idle, .unreachable: break
        }
        let text = title.text
        if !text.isEmpty {
            out.append(NSAttributedString(string: (out.length > 0 ? " " : "") + text, attributes: [.font: font]))
        }
        if title.needsYou {
            if out.length > 0 { out.append(NSAttributedString(string: " ", attributes: [.font: font])) }
            out.append(attachment("circle.fill", .systemBlue, size: 6))
        }
        if out.length > 0 { out.insert(NSAttributedString(string: " ", attributes: [.font: font]), at: 0) }
        return out
    }

    private static func attachment(_ symbol: String, _ color: NSColor, size: CGFloat) -> NSAttributedString {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = false
        let attachment = NSTextAttachment()
        attachment.image = image
        if let image { attachment.bounds = CGRect(x: 0, y: -1, width: image.size.width, height: image.size.height) }
        return NSAttributedString(attachment: attachment)
    }
}
