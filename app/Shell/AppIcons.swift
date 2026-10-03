// Serves app icons to the panel: trisplit-icon://app/<percent-encoded name> -> 128x128 PNG.
import AppKit
import WebKit

final class AppIconSchemeHandler: NSObject, WKURLSchemeHandler {
    private var cache: [String: Data] = [:]
    private let lock = NSLock()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        var name = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        name = name.removingPercentEncoding ?? name
        if let r = name.range(of: "#\\d+$", options: .regularExpression) { name.removeSubrange(r) }
        let data = pngData(for: name)
        let status = data == nil ? 404 : 200
        let headers = ["Content-Type": "image/png", "Cache-Control": "max-age=300"]
        if let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) {
            task.didReceive(resp)
        }
        if let d = data { task.didReceive(d) }
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func pngData(for base: String) -> Data? {
        lock.lock(); let hit = cache[base]; lock.unlock()
        if let hit = hit { return hit }
        guard let icon = resolve(base), let png = render(icon) else { return nil }
        lock.lock(); cache[base] = png; lock.unlock()
        return png
    }

    private func resolve(_ base: String) -> NSImage? {
        let names = namesFor(base)
        if let img = runningApp(names)?.icon { return img }
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications",
                    "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        for n in names {
            for d in dirs {
                let p = d + "/" + n + ".app"
                if FileManager.default.fileExists(atPath: p) {
                    return NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: p).resolvingSymlinksInPath().path)
                }
            }
        }
        return nil
    }

    private func render(_ img: NSImage) -> Data? {
        let px = 128
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        img.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
