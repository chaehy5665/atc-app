// SPDX-License-Identifier: Apache-2.0
import AppKit
import ATCCore
import WebKit

/// The atc window: one NSWindow with a WKWebView that shows the atc web UI (N7). AppKit only.
/// Routing, the overlay rules and the badge are in ATCCore (`LinkRoute`, `WindowOverlay`, `DockBadge`).
/// The app never calls into the page beyond setting `location.hash`; the page never calls Swift
/// (no script message handler, no injected user scripts).
@MainActor
final class AtcWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, NSMenuItemValidation {
    static let frameName = "atc"

    private let model: AppModel
    /// Called before the window comes forward (the popover closes).
    var onWillShow: (() -> Void)?
    /// True while another app window (the Work window) is open, so closing this one keeps the Dock icon.
    var keepsAppRegular: (() -> Bool)?

    private var window: NSWindow?
    private var webView: WKWebView?
    private var titleObservation: NSKeyValueObservation?
    private var overlayView: OverlayView?
    private var overlay = WindowOverlay()
    /// True once a page has committed: then a link only sets the hash.
    private var committed = false

    init(model: AppModel) {
        self.model = model
    }

    var isOpen: Bool { window != nil }

    // MARK: Showing

    /// Opens the window (or brings it forward) on the tab named by `fragment`.
    func show(fragment: String?) {
        onWillShow?()
        if window == nil { open(fragment: fragment) } else { route(to: fragment) }
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.dockTile.badgeLabel = DockBadge.label(model.feed)
    }

    private func open(fragment: String?) {
        // Regular first, so the window can take focus and the menu bar appears.
        NSApp.setActivationPolicy(.regular)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // RADIO audio plays without a click.
        config.mediaTypesRequiringUserActionForPlayback = []
        // N7a reads this suffix to leave alert sound to the app.
        config.applicationNameForUserAgent = AppIdentity.userAgentName(version: Self.version)
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.autoresizingMask = [.width, .height]
        titleObservation = web.observe(\.title, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateTitle() }
        }

        let overlayView = OverlayView()
        overlayView.autoresizingMask = [.width, .height]

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        win.title = "atc"
        win.minSize = NSSize(width: 900, height: 600)
        win.isReleasedWhenClosed = false
        win.delegate = self
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 820))
        web.frame = container.bounds
        overlayView.frame = container.bounds
        container.addSubview(web)
        container.addSubview(overlayView)
        win.contentView = container

        // First open: 1280x820, centred. After that the remembered frame.
        let hadFrame = UserDefaults.standard.object(forKey: "NSWindow Frame \(Self.frameName)") != nil
        win.setFrameAutosaveName(Self.frameName)
        if !hadFrame { win.center() }

        window = win
        webView = web
        self.overlayView = overlayView
        committed = false
        overlay = WindowOverlay()
        _ = overlay.feedChanged(model.feed.connection)
        applyOverlay()
        load(fragment: fragment)
    }

    private func load(fragment: String?) {
        guard let webView, let url = LinkRoute.pageURL(base: model.baseURL, fragment: fragment) else { return }
        committed = false
        webView.load(URLRequest(url: url))
    }

    /// A loaded page switches tab by hash, with no reload; otherwise the page loads at that tab.
    private func route(to fragment: String?) {
        guard let webView else { return }
        let sameOrigin = webView.url.map { LinkRoute.sameOrigin($0, model.baseURL) } ?? false
        if committed && sameOrigin {
            webView.evaluateJavaScript(LinkRoute.hashScript(fragment: fragment), completionHandler: nil)
        } else {
            load(fragment: fragment)
        }
    }

    // MARK: Feed

    /// Called on every feed change: the badge, the overlay, and one reload when atc returns.
    func feedChanged(_ feed: FeedState) {
        guard window != nil else { return }
        NSApp.dockTile.badgeLabel = DockBadge.label(feed)
        let reload = overlay.feedChanged(feed.connection)
        applyOverlay()
        if reload { reloadPage() }
    }

    private func applyOverlay() {
        overlayView?.show(text: overlay.text)
    }

    private func updateTitle() {
        guard let window else { return }
        let t = webView?.title ?? ""
        window.title = t.isEmpty ? "atc" : t
    }

    // MARK: Menu actions (View)

    @objc func reloadPage() {
        guard let webView else { return }
        if committed { webView.reload() } else { load(fragment: nil) }
    }

    @objc func actualSize() { webView?.pageZoom = 1 }
    @objc func zoomIn() { if let w = webView { w.pageZoom = min(3, w.pageZoom * 1.1) } }
    @objc func zoomOut() { if let w = webView { w.pageZoom = max(0.4, w.pageZoom / 1.1) } }

    /// View items work only while the atc window is the key window, so ⌘R does not clash with the popover's Refresh.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        window?.isKeyWindow ?? false
    }

    // MARK: Closing

    func windowWillClose(_ notification: Notification) {
        // Release the page: no hidden web view and no second /api/events stream.
        titleObservation = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        overlayView = nil
        committed = false
        let closing = window
        window = nil
        closing?.delegate = nil
        closing?.contentView = nil
        // Keep the window object alive until AppKit is done with it.
        DispatchQueue.main.async { _ = closing }
        NSApp.dockTile.badgeLabel = nil
        if !(keepsAppRegular?() ?? false) { NSApp.setActivationPolicy(.accessory) }
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if WindowNavigation.allows(url, base: model.baseURL) {
            // target=_blank to the atc origin is still a new window request: keep it in the one window.
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request); decisionHandler(.cancel); return }
            decisionHandler(.allow)
            return
        }
        // Other origins never load here. A link click goes to the default browser; a frame inside the page is just blocked.
        if navigationAction.targetFrame?.isMainFrame ?? true { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        committed = true
        overlay.pageLoaded()
        applyOverlay()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        overlay.pageFailed()
        applyOverlay()
    }

    // MARK: WKUIDelegate

    /// `window.open` and `target=_blank`: the default browser, never a second web view.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if WindowNavigation.allows(url, base: model.baseURL) { self.webView?.load(navigationAction.request) } else { NSWorkspace.shared.open(url) }
        }
        return nil
    }

    // WebKit answers alert() and confirm() with "cancel" unless the host shows them.
    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        present(message: message, cancellable: false) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        present(message: message, cancellable: true, completion: completionHandler)
    }

    private func present(message: String, cancellable: Bool, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        if cancellable { alert.addButton(withTitle: "Cancel") }
        guard let window else { completion(false); return }
        alert.beginSheetModal(for: window) { completion($0 == .alertFirstButtonReturn) }
    }

    // MARK: Helpers

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// Covers the page with the popover's wording while atc cannot be reached (instead of WebKit's error page).
private final class OverlayView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    private let hint = NSTextField(wrappingLabelWithString: "연결이 돌아오면 자동으로 다시 불러옵니다")

    override var wantsUpdateLayer: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.alignment = .center
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        let stack = NSStackView(views: [label, hint])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
        ])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    func show(text: String?) {
        isHidden = text == nil
        if let text { label.stringValue = text }
    }
}
