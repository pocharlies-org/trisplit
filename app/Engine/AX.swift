// Thin AXUIElement wrappers (the hs.window equivalents). Call from the AX queue.
import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ el: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Seconds an unresponsive app may block a single AX call.
let AX_TIMEOUT: Float = 1.0

enum AX {
    /// Setting the timeout on the system-wide element makes it the global default.
    static func setGlobalTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), AX_TIMEOUT)
    }

    static func app(_ pid: pid_t) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, AX_TIMEOUT)
        return el
    }

    static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        attr(el, name) as? String
    }

    static func bool(_ el: AXUIElement, _ name: String) -> Bool {
        (attr(el, name) as? Bool) ?? false
    }

    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = attr(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ el: AXUIElement, _ name: String) -> [AXUIElement] {
        (attr(el, name) as? [AXUIElement]) ?? []
    }

    @discardableResult
    static func set(_ el: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(el, name as CFString, value) == .success
    }

    @discardableResult
    static func setBool(_ el: AXUIElement, _ name: String, _ v: Bool) -> Bool {
        set(el, name, (v ? kCFBooleanTrue : kCFBooleanFalse)!)
    }

    @discardableResult
    static func setPosition(_ el: AXUIElement, _ p: CGPoint) -> Bool {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return set(el, kAXPositionAttribute, v)
    }

    @discardableResult
    static func setSize(_ el: AXUIElement, _ s: CGSize) -> Bool {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return set(el, kAXSizeAttribute, v)
    }

    static func windowID(_ el: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(el, &id) == .success && id != 0 ? id : nil
    }

    /// Current position+size (nil when either attribute is unreadable).
    static func frame(_ el: AXUIElement) -> Rect? {
        guard let pv = attr(el, kAXPositionAttribute), let sv = attr(el, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &p),
              AXValueGetValue(sv as! AXValue, .cgSize, &sz) else { return nil }
        return Rect(x: p.x, y: p.y, w: sz.width, h: sz.height)
    }

    static func raise(_ el: AXUIElement) {
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
    }
}

/// An AX window plus its CGWindowID (0 when unknown) and owning pid.
struct AXWindow: @unchecked Sendable {
    let el: AXUIElement
    let id: CGWindowID
    let pid: pid_t

    init(_ el: AXUIElement, pid: pid_t) {
        self.el = el
        self.id = AX.windowID(el) ?? 0
        self.pid = pid
    }

    /// hs.window:isStandard(): subrole AXStandardWindow.
    var isStandard: Bool { AX.string(el, kAXSubroleAttribute) == kAXStandardWindowSubrole }
    var isMinimized: Bool { AX.bool(el, kAXMinimizedAttribute) }
    var isFullscreen: Bool { AX.bool(el, "AXFullScreen") }
    var title: String { AX.string(el, kAXTitleAttribute) ?? "" }
}

/// hs.application:allWindows() (current Space only, like Hammerspoon).
func axWindows(pid: pid_t) -> [AXWindow] {
    AX.elements(AX.app(pid), kAXWindowsAttribute).map { AXWindow($0, pid: pid) }
}

/// Lua visibleWindows(): standard, not minimized, sorted by window id.
func visibleWindows(pid: pid_t) -> [AXWindow] {
    axWindows(pid: pid)
        .filter { $0.isStandard && !$0.isMinimized }
        .enumerated()
        .sorted { $0.element.id != $1.element.id ? $0.element.id < $1.element.id : $0.offset < $1.offset }
        .map { $0.element }
}

/// Lua anyWindow(): first standard or minimized window.
func anyWindow(pid: pid_t) -> AXWindow? {
    axWindows(pid: pid).first { $0.isStandard || $0.isMinimized }
}

/// Lua findWindow(): anyWindow polled 40 x 100 ms. Blocking: AX queue only.
func findWindow(pid: pid_t) -> AXWindow? {
    for _ in 0..<40 {
        if let w = anyWindow(pid: pid) { return w }
        usleep(100_000)
    }
    return nil
}

/// hs.window.focusedWindow(): focused window of the focused application.
func focusedWindow() -> AXWindow? {
    let sys = AXUIElementCreateSystemWide()
    guard let app = AX.element(sys, kAXFocusedApplicationAttribute) else { return nil }
    AXUIElementSetMessagingTimeout(app, AX_TIMEOUT)
    var pid: pid_t = 0
    guard AXUIElementGetPid(app, &pid) == .success,
          let w = AX.element(app, kAXFocusedWindowAttribute),
          AX.string(w, kAXRoleAttribute) == kAXWindowRole else { return nil }  // degraded AX returns the app element
    return AXWindow(w, pid: pid)
}

/// Lua placeWindow(): unminimize, leave fullscreen, then position -> size -> position
/// (the second move fixes cross-screen moves clamped by the old screen's size).
func placeWindow(_ w: AXWindow, _ f: Rect) {
    if w.isMinimized { AX.setBool(w.el, kAXMinimizedAttribute, false) }
    if w.isFullscreen {
        AX.setBool(w.el, "AXFullScreen", false)
        usleep(700_000)
    }
    let p = CGPoint(x: f.x, y: f.y)
    AX.setPosition(w.el, p)
    AX.setSize(w.el, CGSize(width: f.w, height: f.h))
    AX.setPosition(w.el, p)
}

/// hs.window:focus(): front the app, make the window main and raise it.
func focusWindow(_ w: AXWindow) {
    AX.setBool(AX.app(w.pid), kAXFrontmostAttribute, true)
    AX.setBool(w.el, kAXMainAttribute, true)
    AX.raise(w.el)
    NSRunningApplication(processIdentifier: w.pid)?.activate(options: [])
}
