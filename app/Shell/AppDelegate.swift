// Native shell: menu bar item, hotkeys, panel, HUD, URL scheme.
import AppKit
import ApplicationServices

let TRISPLIT_BUNDLE_ID = "com.dibanez.trisplit"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var engine: Engine!
    private var panel: PanelController!
    private var status: StatusMenu!
    private let hud = HUD()
    private let hotkeys = Hotkeys()
    private var pendingURLs: [URL] = []
    private var hotkeysOn = false
    private var lockFD: Int32 = -1

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if activateOtherInstance() {
            NSApp.terminate(nil)
            return
        }
        if !acquireLock() {
            NSLog("trisplit: lock ocupado por otra instancia, saliendo")
            NSApp.terminate(nil)
            return
        }

        let engine = Engine()
        self.engine = engine
        engine.log("arranque: estado en \(engine.statePath)")

        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            let ok = AXIsProcessTrustedWithOptions(opts)
            engine.log("sin permiso de Accesibilidad: solicitado (trusted=\(ok))")
        }

        panel = PanelController(engine: engine)
        engine.onPush = { [weak self] js in self?.panel.evaluate(js) }
        engine.onHidePanel = { [weak self] in self?.panel.hide() }
        engine.onRaisePanel = { [weak self] in self?.panel.bringToFront() }
        engine.onHUD = { [weak self] msg in self?.hud.show(msg) }

        status = StatusMenu(engine: engine, openPanel: { [weak self] in self?.openPanel() },
                            takeHotkeys: { [weak self] in self?.takeHotkeys(userInitiated: true) },
                            hotkeysActive: { [weak self] in self?.hotkeysOn ?? false })

        if hotkeys.installStatus != noErr { engine.log("InstallEventHandler falló (OSStatus \(hotkeys.installStatus))") }
        takeHotkeys(userInitiated: false)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let a = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard a?.bundleIdentifier == HAMMERSPOON_BUNDLE_ID, let self, !self.hotkeysOn else { return }
            self.engine.log("Hammerspoon terminado: registrando atajos")
            self.takeHotkeys(userInitiated: false)
        }

        engine.startWatching()
        if !pendingURLs.isEmpty { application(NSApp, open: pendingURLs); pendingURLs = [] }
    }

    func openPanel() { panel?.show() }

    /// Registers the 21 hotkeys unless Hammerspoon v1 would fire on the same combos.
    /// Hammerspoon's state is checked when this runs, so a later retry picks up a quit Hammerspoon.
    private func takeHotkeys(userInitiated: Bool) {
        guard !hotkeysOn else { return }
        if shouldSkipHotkeys() {
            engine.log("hotkeys omitidos: Hammerspoon v1 activo (TRISPLIT_FORCE_HOTKEYS=1 para forzar)")
            hud.show(HUD_HS_ACTIVE, duration: userInitiated ? 2.5 : 2)
            return
        }
        registerTrisplitHotkeys(hotkeys, engine: engine) { [weak self] in self?.openPanel() }
        hotkeysOn = true
        engine.log("hotkeys registrados: \(hotkeys.registered)/21")
        for f in hotkeys.failed { engine.log("hotkey no registrado: \(f)") }
    }

    /// flock on <state dir>/.lock; the fd stays open for the process lifetime.
    private func acquireLock() -> Bool {
        let path = resolveStatePath(env: ProcessInfo.processInfo.environment, home: NSHomeDirectory()).path
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let fd = Darwin.open(dir + "/.lock", O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { return true }  // can't lock: fall back to the running-apps check
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { Darwin.close(fd); return false }
        lockFD = fd
        return true
    }

    /// Single instance: hand off to the running copy.
    private func activateOtherInstance() -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let other = NSRunningApplication.runningApplications(withBundleIdentifier: TRISPLIT_BUNDLE_ID)
            .first(where: { $0.processIdentifier != me }) else { return false }
        other.activate(options: [])
        NSLog("trisplit: ya hay otra instancia (pid %d), saliendo", other.processIdentifier)
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPanel()
        return true
    }

    /// trisplit://apply | trisplit://panel | trisplit://next
    func application(_ application: NSApplication, open urls: [URL]) {
        guard engine != nil else { pendingURLs += urls; return }
        for url in urls where url.scheme == "trisplit" {
            let cmd = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
            switch cmd {
            case "apply": engine.applyConfig()
            case "panel": openPanel()
            case "next": engine.cycleConfig()
            default: engine.log("URL desconocida: \(url.absoluteString)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
