// Renders panel.html with the real AppIconSchemeHandler and a fixture state to PNG (2x),
// once per appearance. Not part of the app. Run via `make screenshots`.
// Usage: screenshot <panel.html> <state.json> <out-dir>   (writes screenshot-light.png / -dark.png)
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count == 4 else { FileHandle.standardError.write("usage: screenshot <panel.html> <state.json> <out-dir>\n".data(using: .utf8)!); exit(1) }
let htmlURL = URL(fileURLWithPath: args[1]).standardizedFileURL
guard let stateJSON = try? String(contentsOfFile: args[2], encoding: .utf8) else { print("cannot read \(args[2])"); exit(1) }
let outDir = URL(fileURLWithPath: args[3])
let size = NSSize(width: 1100, height: 640)

final class Shot: NSObject, WKNavigationDelegate {
    let wv: WKWebView
    let name: String
    let state: String
    let outDir: URL
    let size: NSSize
    let done: () -> Void
    init(wv: WKWebView, name: String, state: String, outDir: URL, size: NSSize, done: @escaping () -> Void) {
        self.wv = wv; self.name = name; self.state = state; self.outDir = outDir; self.size = size; self.done = done
    }

    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        w.evaluateJavaScript("window.trisplitSetState(\(self.state)); 1") { _, err in
            if let err = err { print("setState failed: \(err)"); exit(1) }
            // Let the icon scheme requests finish.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                w.evaluateJavaScript("document.querySelectorAll('.ic.fallback').length") { r, _ in
                    print("\(self.name): fallback initials = \(r ?? "?")")
                    let cfg = WKSnapshotConfiguration()
                    cfg.rect = CGRect(origin: .zero, size: self.size)
                    cfg.snapshotWidth = NSNumber(value: Double(self.size.width) * 2)
                    w.takeSnapshot(with: cfg) { img, e in
                        guard let img = img, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
                              let png = rep.representation(using: .png, properties: [:]) else { print("snapshot failed: \(String(describing: e))"); exit(1) }
                        let out = self.outDir.appendingPathComponent("screenshot-\(self.name).png")
                        try? png.write(to: out)
                        print("wrote \(out.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
                        self.done()
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var keep: [AnyObject] = []
let modes: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

func run(_ i: Int) {
    if i >= modes.count { exit(0) }
    let (name, ap) = modes[i]
    let cfg = WKWebViewConfiguration()
    cfg.setURLSchemeHandler(AppIconSchemeHandler(), forURLScheme: "trisplit-icon")
    let wv = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: cfg)
    wv.appearance = NSAppearance(named: ap)
    let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: ap)
    win.contentView = wv
    win.orderBack(nil)
    let shot = Shot(wv: wv, name: name, state: stateJSON, outDir: outDir, size: size) { run(i + 1) }
    wv.navigationDelegate = shot
    keep += [wv, win, shot]
    wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
}
DispatchQueue.main.async { run(0) }
app.run()
