// SPDX-License-Identifier: Apache-2.0
import Foundation

// N7: the rules behind the atc window. The app target only hosts the WKWebView and calls these.

/// Where a click-through opens (Settings, D10).
public enum LinkPreference: String, Sendable, CaseIterable {
    case window, browser
}

/// Where one link opens.
public enum LinkRoute: Equatable, Sendable {
    /// In the atc window; the fragment (without `#`, still percent-encoded) is the tab, nil for none.
    case window(fragment: String?)
    case browser(URL)

    /// The atc origin (same scheme, host and port as `base`) opens in the window, everything else in the browser.
    /// The Settings switch "browser", or `modifier` (⌥ held), sends every link to the browser.
    public static func decide(url: URL, base: URL, preference: LinkPreference, modifier: Bool) -> LinkRoute {
        guard preference == .window, !modifier, sameOrigin(url, base) else { return .browser(url) }
        return .window(fragment: URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment)
    }

    /// Hosts a Work row (GitHub PR, Linear issue) may open. Titles and URLs from those services are untrusted data.
    public static let workHosts: Set<String> = ["github.com", "linear.app"]

    /// A link taken from GitHub or Linear data: the URL itself if it is https on a work host (no user info,
    /// default port), else nil and nothing opens. Always opens in the browser, never in the atc window.
    public static func workLink(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), workHosts.contains(host),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443
        else { return nil }
        return url
    }

    /// Scheme, host and port equal; the default port of http (80) and https (443) counts as given.
    public static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        guard let x = origin(a), let y = origin(b) else { return false }
        return x == y
    }

    private static func origin(_ url: URL) -> [String]? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty
        else { return nil }
        return [scheme, host, String(url.port ?? (scheme == "https" ? 443 : 80))]
    }

    /// JavaScript that switches an already loaded atc page to a tab without a reload, like the web's own alert click.
    /// The fragment is quoted as a JS string; only Swift builds it, nothing is injected into the page ahead of time.
    public static func hashScript(fragment: String?) -> String {
        var s = ""
        for ch in fragment ?? "" {
            switch ch {
            case "\\": s += "\\\\"
            case "\"": s += "\\\""
            case "\n": s += "\\n"
            case "\r": s += "\\r"
            case "\u{2028}": s += "\\u2028"
            case "\u{2029}": s += "\\u2029"
            default: s.append(ch)
            }
        }
        return "location.hash = \"\(s)\";"
    }

    /// The first page load: `base/#fragment`.
    public static func pageURL(base: URL, fragment: String?) -> URL? {
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        guard let fragment, !fragment.isEmpty else { return URL(string: root + "/") }
        return URL(string: root + "/#" + fragment)
    }
}

/// What the window's navigation delegate lets load.
public enum WindowNavigation {
    /// Only the configured atc origin loads in the window (also `about:blank`, which WebKit uses internally).
    public static func allows(_ url: URL, base: URL) -> Bool {
        url.absoluteString == "about:blank" || LinkRoute.sameOrigin(url, base)
    }
}

/// The user agent suffix N7a reads: `ANNUNCIATOR/<version>`.
public enum AppIdentity {
    public static func userAgentName(version: String) -> String { "ANNUNCIATOR/\(version)" }
}

/// The Dock badge while the window is open: the same number as the menu bar title (WARNING + CAUTION); nil for none.
public enum DockBadge {
    public static func label(_ feed: FeedState) -> String? {
        guard feed.connection == .live, let c = feed.summary?.counts else { return nil }
        let n = c.warning + c.caution
        return n > 0 ? String(n) : nil
    }
}

/// When the native overlay covers the page, and when the page reloads.
/// The text is the popover's (`PanelContent`), so the two never disagree.
public struct WindowOverlay: Equatable, Sendable {
    public private(set) var feedDown = false
    public private(set) var navigationFailed = false
    private var feedNotice = PanelContent.unreachableNotice

    public init() {}

    public var text: String? { feedDown ? feedNotice : (navigationFailed ? PanelContent.unreachableNotice : nil) }

    /// Follow the feed. Returns true when it came back and the page should reload once
    /// (its own event stream dropped with the connection). `connecting` changes nothing.
    public mutating func feedChanged(_ connection: Connection) -> Bool {
        switch connection {
        case .unreachable:
            feedDown = true
            feedNotice = PanelContent.unreachableNotice
        case .unsupported:
            feedDown = true
            feedNotice = PanelContent.unsupportedNotice
        case .live:
            let wasDown = feedDown
            feedDown = false
            if wasDown { navigationFailed = false }
            return wasDown
        case .connecting:
            break
        }
        return false
    }

    /// `didFailProvisionalNavigation`: WebKit's error page never shows.
    public mutating func pageFailed() { navigationFailed = true }

    /// A page committed (also after Reload from the menu).
    public mutating func pageLoaded() { navigationFailed = false }
}
