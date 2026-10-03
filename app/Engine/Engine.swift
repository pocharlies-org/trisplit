// Native window engine: port of init.lua (layouts, slots, panel actions, arrangement).
// State and callbacks live on main; AX calls and blocking polls run on `axQueue`.
import AppKit
import ApplicationServices

let HUD_LOCKED = "Pantalla bloqueada: layout cancelado"
let HUD_SAVE_EMPTY = "Error: el panel envió 0 configuraciones; no se guarda"
let AX_SETTINGS_URL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
let HUD_ARRANGE_RESTORED = "Disposición original restaurada"
let HUD_ARRANGE_APPLIED = "Disposición aplicada a macOS"
let HUD_ARRANGE_FAILED = "No se pudo aplicar la disposición"
let HUD_NEED_AX = "Trisplit necesita permiso de Accesibilidad"

final class Engine: @unchecked Sendable {
    private(set) var state: TrisplitState
    let statePath: String

    /// native -> panel JS (`window.trisplitSetState(...)`).
    var onPush: ((String) -> Void)?
    var onHidePanel: (() -> Void)?
    var onRaisePanel: (() -> Void)?
    var onHUD: ((String) -> Void)?
    var onStateChanged: (() -> Void)?
    var log: (String) -> Void = Engine.defaultLog

    let axQueue = DispatchQueue(label: "trisplit.ax", qos: .userInitiated)
    private var pushItem: DispatchWorkItem?
    /// Last script sent to the panel (main thread). AX destroy notifications fire constantly;
    /// identical pushes are skipped so the panel is not re-rendered for nothing.
    private var lastPushed: String?
    private var observers: [pid_t: AXObserver] = [:]
    private var watching = false

    init(env: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()) {
        let r = resolveStatePath(env: env, home: home)
        statePath = r.path
        // TRISPLIT_STATE override: hermetic, never import into/next to the real state.
        if !r.overridden {
            importLegacyIfNeeded(newPath: r.path, legacyPath: legacyStatePath(home: home))
        }
        let names = sortScreens(currentScreens()).map { $0.name }
        let lr = loadState(path: r.path, defaultConfig: { defaultConfig(sortedScreenNames: names) })
        state = lr.state
        if let b = lr.backupPath { log("estado ilegible, copia en \(b)") }
        AX.setGlobalTimeout()
    }

    // MARK: - Logging

    static let defaultLog: (String) -> Void = { msg in
        NSLog("trisplit: %@", msg)
        let dir = NSHomeDirectory() + "/Library/Logs/Trisplit"
        let path = dir + "/trisplit.log"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            h.closeFile()
        } else {
            try? Data(line.utf8).write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - State

    func save() {
        do { try saveState(state, path: statePath) } catch { log("no se pudo guardar el estado: \(error)") }
        onStateChanged?()
    }

    func screens() -> [ScreenInfo] { sortScreens(currentScreens()) }

    func setActive(_ n: Int) {
        guard n >= 1 && n <= state.configs.count else { return }
        state.active = n
        save()
        applyConfig(completion: nil)
        schedulePush()
    }

    private var sortedNames: [String] { screens().map { $0.name } }

    private func axGuard(_ completion: ((Bool) -> Void)?) -> Bool {
        if AXIsProcessTrusted() { return true }
        log(HUD_NEED_AX)
        onHUD?(HUD_NEED_AX)
        completion?(false)
        return false
    }

    /// Runs `work` on the AX queue and delivers its result on main.
    private func onAX<T>(_ work: @escaping () -> T, then done: @escaping (T) -> Void) {
        axQueue.async {
            let r = work()
            DispatchQueue.main.async { done(r) }
        }
    }

    /// Thread-safe log from the AX queue.
    private func axLog(_ m: String) { DispatchQueue.main.async { self.log(m) } }

    // MARK: - Placement (AX queue)

    /// Diagnostic: placeWindow plus immediate AX read-back of the frame.
    private func placeWindowLogged(_ w: AXWindow, _ f: Rect) {
        placeWindow(w, f)
        let name = NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? "pid \(w.pid)"
        let tag = "\(name) \"\(w.title)\" id=\(w.id)"
        let fmt: (Rect?) -> String = { r in
            guard let r else { return "nil" }
            return "(\(Int(r.x)),\(Int(r.y)) \(Int(r.w))x\(Int(r.h)))"
        }
        axLog("place \(tag) target=\(fmt(f)) readback=\(fmt(AX.frame(w.el)))")
    }

    /// placeApp outside applyConfig (single placement, no per-run dedupe).
    private func placeApp(_ spec: String, _ frame: Rect) -> Bool {
        var placed = Set<CGWindowID>()
        return placeApp(spec, frame, placed: &placed)
    }

    /// Lua placeApp(). Blocking; AX queue only. Closed apps are skipped, never launched.
    /// `placed`: window ids already placed in this run; a window is never placed twice.
    private func placeApp(_ spec: String, _ frame: Rect, placed: inout Set<CGWindowID>) -> Bool {
        let (name, idx) = parseSpec(spec)
        let names = namesFor(name)
        guard let app = runningApp(names) else {
            axLog("no abierta, omitida: \(name)")
            return true
        }
        var pid = app.processIdentifier
        var win = pickWindow(slotWindows(pid: pid), idx: idx)
        if win == nil {
            app.activate(options: [])
            win = findWindow(pid: pid)
        }
        if win == nil {
            launchOrFocus(names[0])
            win = findWindow(pid: pid)
        }
        if win == nil {
            axLog("reiniciando \(name) para abrir ventana")
            runProcess("/bin/kill", ["-9", String(pid)])
            for _ in 0..<50 {
                if app.isTerminated || kill(pid, 0) != 0 { break }  // signal 0 = existence probe
                usleep(100_000)
            }
            launchOrFocus(names[0])
            if let a = ensureRunning(names) {
                pid = a.processIdentifier
                win = findWindow(pid: pid)
            }
        }
        guard let w = win else {
            axLog("sin ventana para: \(name)")
            return false
        }
        if w.id != 0 && placed.contains(w.id) {
            axLog("ya colocada en otro slot, omitida: \(spec)")
            return true
        }
        placeWindowLogged(w, frame)
        if w.id != 0 { placed.insert(w.id) }
        return true
    }

    // MARK: - Actions

    /// Lua applyConfig().
    /// `keepPanelOnTop`: the panel is open (Aplicar): re-activate Trisplit after raising the windows.
    func applyConfig(keepPanelOnTop: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard let cfg = state.activeConfig else { completion?(false); return }
        if screenLocked() {
            log(HUD_LOCKED)
            onHUD?(HUD_LOCKED)
            completion?(false)
            return
        }
        guard axGuard(completion) else { return }
        var jobs: [(String, Rect)] = []
        for s in screens() {
            guard let g = cfg.monitors[s.name] else { continue }
            for (i, app) in g.slots.enumerated() where !app.isEmpty && app != SPAN_MARK {
                let span = spanCount(g.slots, index: i + 1, cols: g.cols)
                jobs.append((app, gridFrame(s.visible, index: i + 1, cols: g.cols, rows: g.rows, span: span)))
            }
        }
        log("applyConfig start jobs=\(jobs.count)")
        onAX({ [self] in
            // Resolve every job to its target window first, then dedupe: a window claimed by
            // several slots goes to the exact-index slot (last one on ties), see slotWinners.
            let resolved: [(win: AXWindow?, exact: Bool)] = jobs.map { job in
                let (name, idx) = parseSpec(job.0)
                guard let app = runningApp(namesFor(name)) else { return (nil, false) }
                let wins = slotWindows(pid: app.processIdentifier)
                return (pickWindow(wins, idx: idx), idx <= wins.count)
            }
            let winners = slotWinners(resolved.map { (id: Int($0.win?.id ?? 0), exact: $0.exact) })
            let targets = resolved.map { $0.win }
            var ok = true
            var placed = Set<CGWindowID>()
            var order: [CGWindowID] = []   // placed windows in slot order, for the raise phase
            let focusedBefore = focusedWindow()?.id
            for (i, (app, f)) in jobs.enumerated() {
                guard winners.contains(i) else {
                    axLog("ya colocada en otro slot, omitida: \(app)")
                    continue
                }
                if let w = targets[i], w.id != 0, !placed.contains(w.id) {
                    placeWindowLogged(w, f)
                    placed.insert(w.id)
                    order.append(w.id)
                } else {
                    let before = placed
                    if !placeApp(app, f, placed: &placed) { ok = false }
                    order.append(contentsOf: placed.subtracting(before))
                }
            }
            raisePlaced(order, previouslyFocused: focusedBefore)
            return ok
        }, then: { [self] ok in
            if keepPanelOnTop { onRaisePanel?() }
            log("applyConfig end jobs=\(jobs.count) ok=\(ok)")
            completion?(ok)
        })
    }

    /// Brings the placed windows above other apps' windows (applyConfig only moves/resizes).
    /// Raises in slot order with a short gap so WindowServer applies each activation; the final
    /// focus (see raiseOrder) goes last. AX queue only.
    private func raisePlaced(_ order: [CGWindowID], previouslyFocused: CGWindowID?) {
        let seq = raiseOrder(placed: order, previouslyFocused: previouslyFocused)
        guard !seq.isEmpty else { return }
        var byID: [CGWindowID: AXWindow] = [:]
        for a in runningApps() where a.activationPolicy == .regular {
            for w in slotWindows(pid: a.processIdentifier) where w.id != 0 { byID[w.id] = w }
        }
        for id in seq {
            guard let w = byID[id] else { continue }
            let name = NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? "pid \(w.pid)"
            focusWindow(w)
            axLog("raise \(name) id=\(id)")
            usleep(40_000)
        }
        axLog("foco final id=\(seq.last!)")
    }

    /// Lua cycle hotkey.
    func cycleConfig() {
        guard !state.configs.isEmpty else { return }
        state.active = nextActive(state.active, count: state.configs.count)
        save()
        applyConfig(completion: nil)
        schedulePush()
    }

    /// Lua moveFrontToSlot(n).
    func moveFrontToSlot(_ n: Int) {
        let slots = flatSlots(state.activeConfig, sortedScreenNames: sortedNames)
        guard n >= 1 && n <= slots.count else { return }
        let slot = slots[n - 1]
        guard let s = screenNamed(slot.screen, in: screens()) else {
            log("sin pantalla \(slot.screen)")
            return
        }
        guard axGuard(nil) else { return }
        let frame = gridFrame(s.visible, index: slot.idx, cols: slot.cols, rows: slot.rows, span: slot.span)
        // Capture the config now: the active one may change while AX work runs.
        let ai = state.active - 1
        onAX({ () -> (String, Int)? in
            guard let w = focusedWindow() else { return nil }
            self.placeWindowLogged(w, frame)
            focusWindow(w)
            let name = NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? ""
            let wins = slotWindows(pid: w.pid)
            let idx = (wins.firstIndex { $0.id != 0 && $0.id == w.id } ?? 0) + 1
            return name.isEmpty ? nil : (name, idx)
        }, then: { [self] r in
            guard let (name, idx) = r else { return }
            guard state.configs.indices.contains(ai),
                  var g = state.configs[ai].monitors[slot.screen],
                  g.slots.indices.contains(slot.idx - 1) || slot.idx - 1 < g.cols * g.rows else { return }
            while g.slots.count < slot.idx { g.slots.append("") }
            g.slots[slot.idx - 1] = slotSpec(app: name, idx: idx)
            state.configs[ai].monitors[slot.screen] = g
            save()
            schedulePush()
        })
    }

    /// Lua focusSlot(n).
    func focusSlot(_ n: Int, completion: ((Bool) -> Void)? = nil) {
        let slots = flatSlots(state.activeConfig, sortedScreenNames: sortedNames)
        guard n >= 1 && n <= slots.count, !slots[n - 1].app.isEmpty else { completion?(false); return }
        guard axGuard(completion) else { return }
        let (name, idx) = parseSpec(slots[n - 1].app)
        let names = namesFor(name)
        onAX({
            if let a = runningApp(names), let w = pickWindow(slotWindows(pid: a.processIdentifier), idx: idx) {
                if w.isMinimized { AX.setBool(w.el, kAXMinimizedAttribute, false) }
                focusWindow(w)
            } else {
                launchOrFocus(names[0])
            }
            return true
        }, then: { ok in completion?(ok) })
    }

    /// Lua liveMove(screenName, idx, app).
    func liveMove(screen: String, idx: Int, app: String, completion: ((Bool) -> Void)? = nil) {
        guard !app.isEmpty, let s = screenNamed(screen, in: screens()),
              let g = state.activeConfig?.monitors[screen] else { completion?(false); return }
        guard axGuard(completion) else { return }
        let f = gridFrame(s.visible, index: idx, cols: g.cols, rows: g.rows,
                          span: spanCount(g.slots, index: idx, cols: g.cols))
        // Capture the other slots now: the active config may change while AX work runs.
        var others: [String] = []
        if let cfg = state.activeConfig {
            for sc in screens() {
                guard let mg = cfg.monitors[sc.name] else { continue }
                for (i, a) in mg.slots.enumerated() where !a.isEmpty && a != SPAN_MARK {
                    if sc.name == screen && i + 1 == idx { continue }
                    others.append(a)
                }
            }
        }
        onAX({ [self] in
            var placed = Set<CGWindowID>()
            let ok = placeApp(app, f, placed: &placed)
            if ok && !placed.isEmpty { minimizeCovered(by: f, placer: app, keep: placed, otherSlots: others) }
            return ok
        }, then: { ok in completion?(ok) })
    }

    /// Minimizes windows that are not in the grid and whose center lies inside `f` (just
    /// covered by `placer`). Windows resolved for any other slot of the config are kept. AX queue only.
    private func minimizeCovered(by f: Rect, placer: String, keep placed: Set<CGWindowID>, otherSlots: [String]) {
        var keep = placed
        for spec in otherSlots {
            let (name, idx) = parseSpec(spec)
            guard let a = runningApp(namesFor(name)),
                  let w = pickWindow(slotWindows(pid: a.processIdentifier), idx: idx), w.id != 0 else { continue }
            keep.insert(w.id)
        }
        var wins: [CGWindowID: AXWindow] = [:]
        var candidates: [(id: UInt32, frame: Rect)] = []
        for a in runningApps() where a.activationPolicy == .regular {
            for w in visibleWindows(pid: a.processIdentifier) where w.id != 0 {
                guard let fr = AX.frame(w.el) else { continue }
                wins[w.id] = w
                candidates.append((id: w.id, frame: fr))
            }
        }
        for id in windowsCovered(by: f, candidates: candidates, keep: keep) {
            guard let w = wins[id] else { continue }
            AX.setBool(w.el, kAXMinimizedAttribute, true)
            let name = NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? "pid \(w.pid)"
            axLog("minimizada (tapada por \(placer)): \(name) \(id)")
        }
    }

    /// Lua panelState(); visible-window enumeration runs on the AX queue.
    func panelState(completion: @escaping (PanelState) -> Void) {
        let st = state
        let scr = screens()
        onAX({ AXIsProcessTrusted() ? visibleApps() : [] }, then: { apps in
            completion(makePanelState(state: st, sortedScreens: scr, apps: apps,
                                      primary: primaryScreen(scr),
                                      hasDisplayplacer: FileManager.default.isExecutableFile(atPath: DISPLAYPLACER),
                                      axTrusted: AXIsProcessTrusted()))
        })
    }

    /// Lua applyArrangement(offsets). Blocking (runs displayplacer).
    func applyArrangement(offsets: [String: Offset]?) -> Result<Void, ArrangeError> {
        guard FileManager.default.isExecutableFile(atPath: DISPLAYPLACER) else {
            return .failure(ArrangeError(ERR_NO_DISPLAYPLACER))
        }
        let list = runProcess(DISPLAYPLACER, ["list"])
        let blocks = parseDisplayplacer(list.out)
        let scr = screens().map { (name: $0.name, full: $0.full) }
        switch arrangementArgs(screens: scr, offsets: offsets, blocks: blocks) {
        case .failure(let e): return .failure(e)
        case .success(let args):
            let r = runProcess(DISPLAYPLACER, args)
            return r.status == 0 ? .success(()) : .failure(ArrangeError("displayplacer salió con \(r.status)"))
        }
    }

    // MARK: - Panel

    /// Debounced push of the panel state (main thread).
    func schedulePush(after delay: TimeInterval = 0.7) {
        pushItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.pushNow() }
        pushItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func pushNow() {
        panelState { [weak self] p in
            guard let self else { return }
            do {
                let js = try panelPushScript(p)
                guard js != self.lastPushed else { return }
                self.lastPushed = js
                self.onPush?(js)
            } catch { self.log("push falló: \(error)") }
        }
    }

    /// Lua handlePanel(json): webkit message body from panel.html.
    func handlePanel(_ body: String) {
        guard let m = JSON.parse(body), let action = m["action"]?.string else {
            log("acción de panel desconocida: \(body)")
            return
        }
        // Any panel message means its local state may differ from the last push
        // (reload, edits, rejected save): the next push must always go through.
        lastPushed = nil
        switch action {
        case "ready":
            schedulePush(after: 0.3)
        case "save":
            let configs = (m["configs"]?.array ?? []).compactMap(Config.from)
            guard !configs.isEmpty else {
                log("save ignorado: 0 configuraciones válidas")
                onHUD?(HUD_SAVE_EMPTY)
                schedulePush(after: 0)
                return
            }
            state.configs = configs
            state.active = m["active"]?.int ?? state.active
            state.normalizeActive()
            save()
            schedulePush()
        case "liveMove":
            liveMove(screen: m["screen"]?.string ?? "", idx: m["idx"]?.int ?? 1,
                     app: m["app"]?.string ?? "", completion: nil)
        case "arrange":
            let offs = offsetsFrom(m["offsets"])
            if state.arrange.isEmpty && !offs.isEmpty {
                state.arrangeOriginal = currentOffsets(screens: screens().map { (name: $0.name, full: $0.full) })
            }
            state.arrange = offs
            save()
        case "resetArrange":
            let original = state.arrangeOriginal
            let restore = original != nil && state.arrange.isEmpty
            let finish: () -> Void = { [self] in
                state.arrange = [:]
                state.arrangeOriginal = nil
                save()
                schedulePush(after: 1.2)
            }
            if restore, let o = original {
                onAX({ [self] in applyArrangement(offsets: o) }, then: { [self] _ in
                    onHUD?(HUD_ARRANGE_RESTORED)
                    finish()
                })
            } else {
                finish()
            }
        case "applyArrange":
            let offs = state.arrange
            onAX({ [self] in applyArrangement(offsets: offs) }, then: { [self] r in
                switch r {
                case .success:
                    state.arrange = [:]
                    save()
                    onHUD?(HUD_ARRANGE_APPLIED)
                    schedulePush(after: 1.2)
                case .failure(let e):
                    log("arrange falló: \(e.message)")
                    onHUD?(HUD_ARRANGE_FAILED)
                    schedulePush(after: 0)
                }
            })
        case "apply":
            applyConfig(keepPanelOnTop: true, completion: nil)
        case "applyAndClose":
            // Hide first: closing the panel makes macOS reactivate the previous app, which
            // must not happen after the raise phase.
            onHidePanel?()
            applyConfig(completion: nil)
        case "close":
            onHidePanel?()
        case "openAXSettings":
            if let u = URL(string: AX_SETTINGS_URL) { NSWorkspace.shared.open(u) }
        default:
            log("acción de panel desconocida: \(action)")
        }
    }

    // MARK: - Live refresh

    /// Workspace + screen notifications and per-app AXObservers -> schedulePush.
    func startWatching() {
        guard !watching else { return }
        watching = true
        let nc = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for n in names {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if let a = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    if n == NSWorkspace.didTerminateApplicationNotification {
                        self.unobserve(a.processIdentifier)
                    } else if n == NSWorkspace.didLaunchApplicationNotification {
                        self.observe(a)
                    }
                }
                self.schedulePush()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.schedulePush() }
        observeAllRunning()
        if !AXIsProcessTrusted() { startAXPoll() }
    }

    func observeAllRunning() {
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular { observe(a) }
    }

    private var axPoll: Timer?
    var onAXGranted: (() -> Void)?

    /// Polls every 2s until Accessibility is granted, then observes apps and pushes.
    private func startAXPoll() {
        guard axPoll == nil else { return }
        axPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self, AXIsProcessTrusted() else { return }
            t.invalidate()
            self.axPoll = nil
            self.log("permiso de Accesibilidad concedido")
            self.observeAllRunning()
            self.schedulePush(after: 0)
            self.onAXGranted?()
        }
    }

    private func observe(_ a: NSRunningApplication) {
        let pid = a.processIdentifier
        guard a.activationPolicy == .regular, observers[pid] == nil, AXIsProcessTrusted() else { return }
        var obs: AXObserver?
        let cb: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let e = Unmanaged<Engine>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { e.schedulePush() }
        }
        guard AXObserverCreate(pid, cb, &obs) == .success, let obs else { return }
        let el = AX.app(pid)
        let ref = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification,
                  kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(obs, el, n as CFString, ref)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }

    private func unobserve(_ pid: pid_t) {
        guard let obs = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }
}
