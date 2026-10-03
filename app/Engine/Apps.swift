// Running-app lookup, launching and process helpers (the hs.application equivalents).
import AppKit

/// Runs an executable without a shell; returns (exit status, stdout). Blocking.
@discardableResult
func runProcess(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// hs.application.launchOrFocus(name) via LaunchServices (`open -a`).
func launchOrFocus(_ name: String) {
    runProcess("/usr/bin/open", ["-a", name])
}

/// Apps that can own windows (regular + accessory), excluding ourselves.
func runningApps() -> [NSRunningApplication] {
    let me = ProcessInfo.processInfo.processIdentifier
    return NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy != .prohibited && $0.processIdentifier != me
            && !$0.isTerminated && $0.localizedName != nil
    }
}

/// First running app for any of `names`: exact localizedName, then `bestMatch`
/// (alias / normalized comparison) across running apps.
func runningApp(_ names: [String]) -> NSRunningApplication? {
    let apps = runningApps()
    for n in names {
        if let a = apps.first(where: { $0.localizedName == n }) { return a }
    }
    return bestMatch(names: names, candidates: apps.map { (name: $0.localizedName ?? "", value: $0) })
}

/// Lua ensureRunning(): running app or launch each name and poll 30 x 100 ms. Blocking.
func ensureRunning(_ names: [String]) -> NSRunningApplication? {
    if let a = runningApp(names) { return a }
    for n in names {
        launchOrFocus(n)
        for _ in 0..<30 {
            if let a = runningApp(names) { return a }
            usleep(100_000)
        }
    }
    return nil
}

/// Lua visibleApps(): regular, not hidden, with at least one visible window.
func visibleApps() -> [PanelApp] {
    var out: [PanelApp] = []
    for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular && !a.isHidden {
        let wins = slotWindows(pid: a.processIdentifier)
        guard !wins.isEmpty, let name = a.localizedName else { continue }
        out.append(PanelApp(name: name, count: wins.count, titles: wins.map { $0.title }, minimized: wins.map { $0.isMinimized }))
    }
    return sortApps(out)
}

/// Screen locked / login window frontmost (Lua screenLocked()).
func screenLocked() -> Bool {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.loginwindow"
}

/// hs.screen equivalents: NSScreen -> ScreenInfo in top-left global coordinates.
func currentScreens() -> [ScreenInfo] {
    let screens = NSScreen.screens
    guard let primaryH = screens.first?.frame.height else { return [] }
    let mainID = CGMainDisplayID()
    return screens.map { s in
        let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let b = CGDisplayBounds(id)
        let vf = s.visibleFrame
        return ScreenInfo(
            name: s.localizedName,
            full: Rect(x: b.origin.x, y: b.origin.y, w: b.width, h: b.height),
            visible: Rect(x: vf.origin.x, y: primaryH - (vf.origin.y + vf.height), w: vf.width, h: vf.height),
            isMain: id == mainID)
    }
}
