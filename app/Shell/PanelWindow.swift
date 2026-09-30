// Reusable panel window: WKWebView on Resources/panel.html, bridged to the engine.
import AppKit
import WebKit

/// Esc closes the panel.
final class PanelNSWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// Breaks the WKUserContentController -> handler retain cycle.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}

final class PanelController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    /// Must match `webkit.messageHandlers.<name>` in panel.html.
    static let handlerName = "trisplit"

    private let engine: Engine
    private var window: PanelNSWindow?
    private var webView: WKWebView?
    private var saveItem: DispatchWorkItem?
    private var pendingSave: String?
    private var escMonitor: Any?
    /// Pushes before the page defines trisplitSetState would throw; hold the latest until ready.
    private var pageReady = false
    private var pendingScript: String?

    init(engine: Engine) {
        self.engine = engine
        super.init()
    }

    private func build() -> PanelNSWindow {
        let w = PanelNSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Trisplit"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 820, height: 520)
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(WeakScriptHandler(self), name: PanelController.handlerName)
        let wv = WKWebView(frame: w.contentLayoutRect, configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        w.contentView = wv
        if let res = Bundle.main.resourceURL {
            let html = res.appendingPathComponent("panel.html")
            wv.loadFileURL(html, allowingReadAccessTo: res)
        } else {
            engine.log("panel: sin Resources en el bundle")
        }
        window = w
        webView = wv
        // WKWebView swallows Esc, so cancelOperation never fires; catch it while the panel is key.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard ev.keyCode == 53, let w = self?.window, w.isKeyWindow else { return ev }
            self?.hide()
            return nil
        }
        return w
    }

    func show() {
        let w = window ?? build()
        if !w.isVisible { center(w) }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        engine.schedulePush(after: 0)
    }

    func hide() { window?.orderOut(nil) }

    func evaluate(_ js: String) {
        guard pageReady else { pendingScript = js; return }
        webView?.evaluateJavaScript(js) { [weak self] _, err in
            if let err { self?.engine.log("panel JS falló: \(PanelController.describe(err))") }
        }
    }

    private func markReady() {
        guard !pageReady else { return }
        pageReady = true
        if let js = pendingScript { pendingScript = nil; evaluate(js) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { markReady() }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        engine.log("panel: proceso web terminado; recargando")
        pageReady = false
        webView.reload()
    }

    /// localizedDescription is generic; WKError userInfo carries the actual exception.
    static func describe(_ err: Error) -> String {
        let info = (err as NSError).userInfo
        var parts = [err.localizedDescription]
        if let m = info["WKJavaScriptExceptionMessage"] { parts.append("msg=\(m)") }
        if let l = info["WKJavaScriptExceptionLineNumber"] { parts.append("line=\(l)") }
        if let u = info["WKJavaScriptExceptionSourceURL"] { parts.append("src=\(u)") }
        return parts.joined(separator: " | ")
    }

    /// Center on the screen that holds the mouse.
    private func center(_ w: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { w.center(); return }
        let size = w.frame.size
        w.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2))
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        let body: String
        if let s = message.body as? String {
            body = s
        } else if JSONSerialization.isValidJSONObject(message.body),
                  let d = try? JSONSerialization.data(withJSONObject: message.body),
                  let s = String(data: d, encoding: .utf8) {
            body = s
        } else {
            engine.log("panel: mensaje no JSON")
            return
        }
        let msg = JSON.parse(body)
        let action = msg?["action"]?.string
        if action == "save" {
            engine.log("panel msg save (coalesced)")
        } else if action == "liveMove" {
            engine.log("panel msg liveMove screen=\(msg?["screen"]?.string ?? "") idx=\(msg?["idx"]?.int ?? 0) app=\(msg?["app"]?.string ?? "")")
        } else {
            engine.log("panel msg \(action ?? "nil")")
        }
        if action == "ready" { markReady() }
        // Panel posts "save" on every edit; coalesce like the v1 shim did.
        if action == "save" {
            pendingSave = body
            saveItem?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.flushSave() }
            saveItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
            return
        }
        // Flush a pending save first so apply/close see the latest configs.
        flushSave()
        engine.handlePanel(body)
    }

    deinit {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
    }

    private func flushSave() {
        saveItem?.cancel()
        saveItem = nil
        guard let b = pendingSave else { return }
        pendingSave = nil
        engine.handlePanel(b)
    }
}
