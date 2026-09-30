// Unit cases for app/Core (parity with init.lua and tests/unit.lua).
import Foundation

// Live geometry of the dev machine, top-left global (CGDisplayBounds / converted visibleFrame).
let ODY = ScreenInfo(name: "Odyssey G95C", full: Rect(x: 0, y: 0, w: 5120, h: 1440),
                     visible: Rect(x: 0, y: 30, w: 5120, h: 1410), isMain: true)
let LC49 = ScreenInfo(name: "LC49G95T", full: Rect(x: 0, y: 1440, w: 5120, h: 1440),
                      visible: Rect(x: 0, y: 1440, w: 5120, h: 1440), isMain: false)
let BUILTIN = ScreenInfo(name: "Built-in Retina Display", full: Rect(x: 5120, y: 2152, w: 1800, h: 1169),
                         visible: Rect(x: 5120, y: 2190, w: 1800, h: 1131), isMain: false)
let LIVE_SCREENS = [BUILTIN, LC49, ODY]
let SORTED_NAMES = ["Odyssey G95C", "LC49G95T", "Built-in Retina Display"]

func named(_ s: [ScreenInfo]) -> [(name: String, full: Rect)] { s.map { ($0.name, $0.full) } }

func geometryTests() {
    test("parseSpec") {
        let a = parseSpec("Safari"); eq(a.name, "Safari"); eq(a.idx, 1)
        let b = parseSpec("Google Chrome#3"); eq(b.name, "Google Chrome"); eq(b.idx, 3)
        let c = parseSpec("App#"); eq(c.name, "App#"); eq(c.idx, 1)
        let d = parseSpec("App#x"); eq(d.name, "App#x"); eq(d.idx, 1)
        let e = parseSpec("App#12"); eq(e.name, "App"); eq(e.idx, 12)
        let f = parseSpec("a#1#2"); eq(f.name, "a#1"); eq(f.idx, 2)
        let g = parseSpec("a#1#x"); eq(g.name, "a#1#x"); eq(g.idx, 1)
        let h = parseSpec("App#١"); eq(h.name, "App#١", "non-ASCII digit is not %d"); eq(h.idx, 1)
        let i = parseSpec(""); eq(i.name, ""); eq(i.idx, 1)
    }
    test("gridFrame") {
        let f = Rect(x: 0, y: 0, w: 1000, h: 500)
        eq(gridFrame(f, index: 1, cols: 1, rows: 1), Rect(x: 0, y: 0, w: 1000, h: 500))
        let w3 = (1000.0 - 8) / 3
        let s2 = gridFrame(f, index: 2, cols: 3, rows: 1)
        near(s2.w, w3); near(s2.x, w3 + 4); near(s2.y, 0); near(s2.h, 500)
        let h2 = (500.0 - 4) / 2
        let q3 = gridFrame(f, index: 3, cols: 2, rows: 2)
        near(q3.x, 0); near(q3.y, h2 + 4); near(q3.w, 498); near(q3.h, h2)
        let t4 = gridFrame(f, index: 4, cols: 3, rows: 2)
        near(t4.x, 0, "3x2 slot 4 starts row 2"); near(t4.y, h2 + 4)
        let l = gridFrame(f, index: 1, cols: 2, rows: 1), r = gridFrame(f, index: 2, cols: 2, rows: 1)
        near(r.x - (l.x + l.w), 4, "gap between 2x1 slots")
        near(r.x + r.w, 1000, "right edge flush")
        eq(gridFrame(f, index: 1, cols: 0, rows: 0), Rect(x: 0, y: 0, w: 1000, h: 500), "clamped to 1x1")
        let off = gridFrame(Rect(x: 5120, y: 2190, w: 1800, h: 1131), index: 2, cols: 2, rows: 1)
        near(off.x, 5120 + 898 + 4); near(off.y, 2190); near(off.w, 898)
        let frac = gridFrame(Rect(x: 0, y: 0, w: 1001, h: 500), index: 1, cols: 2, rows: 1)
        near(frac.w, 498.5, "no flooring")
    }
    test("newMonitorGrid") {
        let g = newMonitorGrid(cols: 3, rows: 2)
        eq(g.slots.count, 6); eq(g.slots, Array(repeating: "", count: 6)); eq(g.cols, 3); eq(g.rows, 2)
    }
    test("slotSpec/pickWindow/floorInt") {
        eq(slotSpec(app: "Safari", idx: 1), "Safari"); eq(slotSpec(app: "Safari", idx: 2), "Safari#2")
        eq(pickWindow([10, 20, 30], idx: 2), 20)
        eq(pickWindow([10, 20, 30], idx: 9), 30, "min(idx,#wins)")
        eq(pickWindow([Int](), idx: 1), nil)
        eq(pickWindow([10], idx: 0), nil)
        eq(floorInt(-1.5), -2); eq(floorInt(2.9), 2); eq(floorInt(.nan), nil); eq(floorInt(.infinity), nil)
        eq(flooredMod(-1, 3), 2); eq(flooredDiv(-1, 3), -1)
    }
    test("pickUnplaced") {
        let id: (Int) -> Int = { $0 }
        // 1 window, specs App#1 + App#2 in the same run: second slot skipped.
        var placed = Set<Int>()
        let a = pickUnplaced([10], idx: 1, placed: placed, id: id)
        eq(a.win, 10); eq(a.alreadyPlaced, false)
        placed.insert(10)
        let b = pickUnplaced([10], idx: 2, placed: placed, id: id)
        eq(b.win, nil, "clamped to already-placed window"); eq(b.alreadyPlaced, true)
        // 2 windows, App#1 + App#2: both placed, distinct.
        placed = []
        let c = pickUnplaced([10, 20], idx: 1, placed: placed, id: id)
        eq(c.win, 10); eq(c.alreadyPlaced, false)
        placed.insert(10)
        let d = pickUnplaced([10, 20], idx: 2, placed: placed, id: id)
        eq(d.win, 20); eq(d.alreadyPlaced, false)
        // Empty placed set == pickWindow; no windows is not "already placed".
        eq(pickUnplaced([10, 20, 30], idx: 9, placed: Set<Int>(), id: id).win, 30)
        let e = pickUnplaced([Int](), idx: 1, placed: [10], id: id)
        eq(e.win, nil); eq(e.alreadyPlaced, false)
    }
}

func stateTests() {
    test("migrate legacy slots") {
        let j = JSON.parse(#"{"name":"Old","slots":[{"screen":"A","app":"X"},{"screen":"A","app":""},{"screen":"B","app":"Y"}]}"#)!
        let c = Config.from(j)!
        eq(c.name, "Old")
        eq(c.monitors["A"]?.slots ?? [], ["X", ""]); eq(c.monitors["B"]?.slots ?? [], ["Y"])
        eq(c.monitors["A"]?.cols, 3); eq(c.monitors["A"]?.rows, 1)
        let enc = JSON.parse(try encodeJSON(c))!
        eq((enc.object ?? [:]).keys.sorted(), ["monitors", "name"], "no top-level slots after migrate")
    }
    test("migrate modern no-op") {
        let src = #"{"name":"M","monitors":{"A":{"cols":2,"rows":1,"slots":["X#2",""]}}}"#
        let c = Config.from(JSON.parse(src)!)!
        eq(c, Config(name: "M", monitors: ["A": MonitorGrid(cols: 2, rows: 1, slots: ["X#2", ""])]))
        eq(try encodeJSONString(c), #"{"monitors":{"A":{"cols":2,"rows":1,"slots":["X#2",""]}},"name":"M"}"#)
    }
    test("JSON numbers are not Bool") {
        let j = JSON.parse(#"{"a":1,"b":0,"c":true,"d":2.5}"#)!
        eq(j["a"], .num(1)); eq(j["b"], .num(0)); eq(j["c"], .bool(true)); eq(j["d"]?.int, 2)
    }
    test("loadState invalid active -> 1") {
        let p = tmpPath("active.json")
        try #"{"active":7,"configs":[{"name":"A","monitors":{}},{"name":"B","monitors":{}}],"arrange":{}}"#
            .write(toFile: p, atomically: true, encoding: .utf8)
        let r = loadState(path: p, defaultConfig: { defaultConfig(sortedScreenNames: SORTED_NAMES) })
        eq(r.usedDefault, false); eq(r.state.active, 1); eq(r.state.configs.count, 2)
        try #"{"active":2,"configs":[{"name":"A","monitors":{}},{"name":"B","monitors":{}}]}"#
            .write(toFile: p, atomically: true, encoding: .utf8)
        let r2 = loadState(path: p, defaultConfig: { defaultConfig(sortedScreenNames: SORTED_NAMES) })
        eq(r2.state.active, 2, "valid active kept"); eq(r2.state.activeConfig?.name, "B")
        try #"{"active":0,"configs":[{"name":"A","monitors":{}}]}"#.write(toFile: p, atomically: true, encoding: .utf8)
        eq(loadState(path: p, defaultConfig: { defaultConfig(sortedScreenNames: []) }).state.active, 1, "0 -> 1")
    }
    test("loadState real fixture") {
        let src = fixture("trisplit.json")
        let before = sha256(src)
        eq(before, "997494ac8b10e6cce22a700794b81cc6378871bafcea255ff25873eb181f9387", "fixture is the real file copy")
        let p = tmpPath("fixture.json")
        try FileManager.default.copyItem(atPath: src, toPath: p)
        let r = loadState(path: p, defaultConfig: { defaultConfig(sortedScreenNames: SORTED_NAMES) })
        eq(r.usedDefault, false); eq(r.state.active, 1); eq(r.state.configs.count, 1)
        let c = r.state.configs[0]
        eq(c.name, "JSDRV")
        eq(c.monitors["LC49G95T"]?.slots ?? [], ["Google Chrome", "Code", "Claude"])
        eq(c.monitors["Odyssey G95C"]?.slots ?? [], ["OpenChamber", "Telegram", "Slack"])
        eq(c.monitors["Built-in Retina Display"]?.cols, 1)
        let wa = c.monitors["Built-in Retina Display"]?.slots.first ?? ""
        eq(wa.unicodeScalars.first?.value, 0x200E, "U+200E kept on load")
        eq(r.state.arrange, [:], "arrange [] -> {}")
        eq(sha256(src), before, "fixture untouched")
        try saveState(r.state, path: p)
        let bytes = [UInt8](FileManager.default.contents(atPath: p)!)
        let needle: [UInt8] = [0x22, 0xE2, 0x80, 0x8E] + Array("WhatsApp\"".utf8)
        check(bytes.indices.contains { i in i + needle.count <= bytes.count && Array(bytes[i..<i + needle.count]) == needle },
              "raw E2 80 8E bytes survive save")
        let text = String(decoding: bytes, as: UTF8.self)
        check(text.contains(#""arrange":{}"#), "arrange encoded as object: \(text)")
        check(!text.contains("\\u200e") && !text.contains("\\u200E"), "not escaped")
        let r2 = loadState(path: p, defaultConfig: { defaultConfig(sortedScreenNames: []) })
        eq(r2.state, r.state, "round trip")
    }
    test("loadState corrupt / missing / no configs") {
        let p = tmpPath("corrupt.json")
        try "{not json".write(toFile: p, atomically: true, encoding: .utf8)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let r = loadState(path: p, defaultConfig: { defaultConfig(sortedScreenNames: SORTED_NAMES) }, now: now)
        eq(r.usedDefault, true)
        check(r.backupPath != nil && r.backupPath!.hasPrefix(p + ".corrupt-"), "backup path \(String(describing: r.backupPath))")
        eq(r.backupPath.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }, "{not json", "backup keeps bytes")
        eq(r.state.configs.first?.name, "Dev")
        eq(loadState(path: p, defaultConfig: { defaultConfig(sortedScreenNames: []) }).usedDefault, false, "default saved")
        let m = tmpPath("sub/dir/missing.json")
        let r2 = loadState(path: m, defaultConfig: { defaultConfig(sortedScreenNames: SORTED_NAMES) })
        eq(r2.usedDefault, true); eq(r2.backupPath, nil)
        check(FileManager.default.fileExists(atPath: m), "missing file saved")
        let e = tmpPath("empty.json")
        try #"{"active":1,"configs":[]}"#.write(toFile: e, atomically: true, encoding: .utf8)
        eq(loadState(path: e, defaultConfig: { defaultConfig(sortedScreenNames: []) }).usedDefault, true, "no configs -> default")
    }
    test("arrangeOriginal round trip") {
        var s = TrisplitState(active: 1, configs: [Config(name: "A", monitors: [:])],
                              arrange: ["X": Offset(dx: 1, dy: 2)], arrangeOriginal: ["X": Offset(dx: 0, dy: 0)])
        let p = tmpPath("ao.json")
        try saveState(s, path: p)
        eq(loadState(path: p, defaultConfig: { defaultConfig(sortedScreenNames: []) }).state, s)
        s.arrangeOriginal = nil
        check(!(try encodeJSONString(s)).contains("arrangeOriginal"), "nil arrangeOriginal omitted")
    }
    test("importLegacyIfNeeded") {
        let legacy = tmpPath("hs/trisplit.json"), target = tmpPath("as/trisplit/trisplit.json")
        try FileManager.default.createDirectory(atPath: tmpPath("hs"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: fixture("trisplit.json"), toPath: legacy)
        let before = sha256(legacy)
        eq(importLegacyIfNeeded(newPath: target, legacyPath: legacy), true)
        eq(sha256(target), before, "byte-identical copy")
        eq(sha256(legacy), before, "legacy untouched")
        check(FileManager.default.fileExists(atPath: legacy), "legacy still exists")
        try "{}".write(toFile: target, atomically: true, encoding: .utf8)
        eq(importLegacyIfNeeded(newPath: target, legacyPath: legacy), false, "existing target not overwritten")
        eq(try String(contentsOfFile: target, encoding: .utf8), "{}")
        eq(importLegacyIfNeeded(newPath: tmpPath("x/y.json"), legacyPath: tmpPath("nope.json")), false)
    }
    test("resolveStatePath") {
        let a = resolveStatePath(env: ["TRISPLIT_STATE": "/tmp/x.json"], home: "/Users/u")
        eq(a.path, "/tmp/x.json"); eq(a.overridden, true)
        let b = resolveStatePath(env: [:], home: "/Users/u")
        eq(b.path, "/Users/u/Library/Application Support/trisplit/trisplit.json"); eq(b.overridden, false)
        eq(resolveStatePath(env: ["TRISPLIT_STATE": ""], home: "/Users/u").overridden, false)
        eq(legacyStatePath(home: "/Users/u"), "/Users/u/.hammerspoon/trisplit.json")
    }
    test("defaultConfig") {
        let c = defaultConfig(sortedScreenNames: SORTED_NAMES)
        eq(c.name, "Dev"); eq(c.monitors.count, 3)
        eq(c.monitors["Odyssey G95C"], MonitorGrid(cols: 3, rows: 1, slots: ["OpenChamber", "Code", "Claude"]))
        eq(c.monitors["LC49G95T"], MonitorGrid(cols: 3, rows: 1, slots: ["", "", ""]))
    }
}

func slotsScreensTests() {
    test("sortScreens") {
        eq(sortScreens(LIVE_SCREENS).map(\.name), SORTED_NAMES)
        let a = ScreenInfo(name: "a", full: Rect(x: 0, y: 0, w: 1, h: 1), visible: Rect(x: 0, y: 0, w: 1, h: 1), isMain: false)
        var b = a; b.name = "b"
        eq(sortScreens([b, a]).map(\.name), ["b", "a"], "stable on ties")
        var neg = a; neg.name = "neg"; neg.full.x = -1920
        eq(sortScreens([a, neg]).map(\.name), ["neg", "a"])
    }
    test("primaryScreen") {
        eq(primaryScreen(LIVE_SCREENS), "Odyssey G95C")
        var o = ODY; o.full.x = 10; o.isMain = false
        var l = LC49; l.isMain = true
        eq(primaryScreen([o, l, BUILTIN]), "LC49G95T", "fallback to main")
        eq(primaryScreen([]), nil)
        eq(screenNamed("LC49G95T", in: LIVE_SCREENS)?.full.y, 1440)
    }
    test("flatSlots") {
        var monitors: [String: MonitorGrid] = [:]
        for n in SORTED_NAMES { monitors[n] = MonitorGrid(cols: 2, rows: 1, slots: ["\(n)-1", "\(n)-2"]) }
        monitors["Ghost"] = MonitorGrid(cols: 1, rows: 1, slots: ["G"])
        let fs = flatSlots(Config(name: "C", monitors: monitors), sortedScreenNames: SORTED_NAMES)
        eq(fs.count, 6, "screens x 2, unknown screen skipped")
        eq(fs.map(\.screen), SORTED_NAMES.flatMap { [$0, $0] })
        eq(fs.map(\.idx), [1, 2, 1, 2, 1, 2])
        eq(fs[3], FlatSlot(screen: "LC49G95T", idx: 2, cols: 2, rows: 1, app: "LC49G95T-2"))
        eq(flatSlots(nil, sortedScreenNames: SORTED_NAMES), [])
    }
    test("nextActive") {
        eq(nextActive(2, count: 2), 1); eq(nextActive(1, count: 2), 2); eq(nextActive(1, count: 1), 1)
        eq(nextActive(3, count: 0), 3)
    }
}

func matchTests() {
    test("namesFor") {
        eq(namesFor("Code"), ["Code", "Visual Studio Code"])
        eq(namesFor("Visual Studio Code"), ["Visual Studio Code", "Code"])
        eq(namesFor("Foo").count, 1)
    }
    test("bestMatch") {
        let cands: [(name: String, value: Int)] = [("WhatsApp", 1), ("Visual Studio Code", 2), ("safari", 3), ("Safari", 4)]
        eq(bestMatch(names: namesFor("\u{200E}WhatsApp"), candidates: cands), 1, "U+200E normalized")
        eq(bestMatch(names: namesFor("Code"), candidates: cands), 2, "alias")
        eq(bestMatch(names: ["Safari"], candidates: cands), 4, "exact beats normalized")
        eq(bestMatch(names: ["SAFARI"], candidates: cands), 3, "normalized first hit")
        eq(bestMatch(names: ["\u{200E}"], candidates: [("", 9)]), nil, "empty normalized skipped")
        eq(bestMatch(names: ["Nope"], candidates: cands), nil)
        eq(normalizedAppName(" \u{200E}WhatsApp "), "whatsapp")
    }
    test("sortApps") {
        let apps = ["slack", "Code", "Arc", "code"].map { PanelApp(name: $0, count: 1, titles: []) }
        eq(sortApps(apps).map(\.name), ["Arc", "Code", "code", "slack"])
        eq(asciiLower("ÉA"), "Éa", "ASCII-only like string.lower")
    }
}

func displayplacerTests() {
    let text = (try? String(contentsOfFile: fixture("displayplacer_list.txt"), encoding: .utf8)) ?? ""
    let blocks = parseDisplayplacer(text)
    test("parseDisplayplacer fixture") {
        check(!text.isEmpty, "fixture readable")
        eq(blocks.map(\.id), ["3B433989-7D1C-41F8-B2A5-0AE31719B4D2", "37D8832A-2D66-02CA-B9F7-8F30A301B230",
                              "BB01DBE1-28FF-4BB1-A62A-03DE13D8685E"])
        guard blocks.count == 3 else { return }
        eq(blocks.map(\.w), [5120, 1800, 5120], "not overwritten by 'Resolutions for rotation'")
        eq(blocks.map(\.h), [1440, 1169, 1440])
        eq(blocks.map(\.hertz), ["120", "120", "120"])
        eq(blocks.map(\.x), [0, 5120, 0]); eq(blocks.map(\.y), [0, 2152, 1440])
        eq(blocks.map(\.main), [true, false, false])
        eq(blocks.map(\.scaling), ["off", "on", "off"])
        eq(blocks.map(\.rot), ["0", "0", "0"]); eq(blocks.map(\.depth), ["8", "8", "8"])
    }
    test("parseDisplayplacer edge cases") {
        let t = "Persistent screen id: AB-1\r\nResolution: 10x20\r\nOrigin: (-5,7)\r\n  Resolution: 99x99\nHertz: 59.94\n"
        let b = parseDisplayplacer(t)
        eq(b.count, 1); eq(b.first?.w, 10); eq(b.first?.x, -5); eq(b.first?.y, 7); eq(b.first?.hertz, "59.94")
        eq(parseDisplayplacer("Resolution: 1x1\n"), [], "fields before an id are ignored")
    }
    let screens = named(sortScreens(LIVE_SCREENS))
    test("currentOffsets") {
        let o = currentOffsets(screens: screens)
        eq(o["Odyssey G95C"], Offset(dx: 0, dy: 0)); eq(o["LC49G95T"], Offset(dx: 0, dy: 1440))
        eq(o["Built-in Retina Display"], Offset(dx: 5120, dy: 2152))
        eq(currentOffsets(screens: [("f", Rect(x: -0.5, y: 10.9, w: 1, h: 1))])["f"], Offset(dx: -1, dy: 10), "floored")
    }
    test("arrangementArgs identity") {
        guard case .success(let args) = arrangementArgs(screens: screens, offsets: currentOffsets(screens: screens), blocks: blocks)
        else { return fail("expected success") }
        eq(args.count, 3)
        eq(args.first, "id:3B433989-7D1C-41F8-B2A5-0AE31719B4D2 res:5120x1440 hz:120 color_depth:8 enabled:true scaling:off origin:(0,0) degree:0")
        eq(args.last, "id:37D8832A-2D66-02CA-B9F7-8F30A301B230 res:1800x1169 hz:120 color_depth:8 enabled:true scaling:on origin:(5120,2152) degree:0")
        guard case .success(let args2) = arrangementArgs(screens: screens, offsets: nil, blocks: blocks)
        else { return fail("nil offsets") }
        eq(args2, args, "nil offsets = current")
    }
    test("arrangementArgs main reassignment") {
        let off = ["Odyssey G95C": Offset(dx: 0, dy: 1440), "LC49G95T": Offset(dx: 0, dy: 0),
                   "Built-in Retina Display": Offset(dx: 5120, dy: 2152)]
        guard case .success(let args) = arrangementArgs(screens: screens, offsets: off, blocks: blocks)
        else { return fail("expected success") }
        eq(args, ["id:3B433989-7D1C-41F8-B2A5-0AE31719B4D2 res:5120x1440 hz:120 color_depth:8 enabled:true scaling:off origin:(0,1440) degree:0",
                  "id:BB01DBE1-28FF-4BB1-A62A-03DE13D8685E res:5120x1440 hz:120 color_depth:8 enabled:true scaling:off origin:(0,0) degree:0",
                  "id:37D8832A-2D66-02CA-B9F7-8F30A301B230 res:1800x1169 hz:120 color_depth:8 enabled:true scaling:on origin:(5120,2152) degree:0"])
    }
    test("arrangementArgs no (0,0) -> sorted, first is main") {
        let off = ["Odyssey G95C": Offset(dx: 200, dy: 0), "LC49G95T": Offset(dx: 100, dy: 1440),
                   "Built-in Retina Display": Offset(dx: 5220, dy: 2152)]
        guard case .success(let args) = arrangementArgs(screens: screens, offsets: off, blocks: blocks)
        else { return fail("expected success") }
        eq(args.map { String($0.prefix(8)) }, ["id:BB01D", "id:3B433", "id:37D88"])
        check(args[0].contains("origin:(0,0)"), args[0])
        check(args[1].contains("origin:(100,-1440)"), args[1])
        check(args[2].contains("origin:(5120,712)"), args[2])
    }
    test("arrangementArgs errors") {
        eq(arrangementArgs(screens: screens, offsets: nil, blocks: []), .failure(ArrangeError(ERR_NO_BLOCKS)))
        let ghost = screens + [("Ghost", Rect(x: 9000, y: 0, w: 10, h: 10))]
        eq(arrangementArgs(screens: ghost, offsets: nil, blocks: blocks),
           .failure(ArrangeError("no se encontró Ghost en displayplacer")))
        var noHz = blocks; noHz[0].hertz = nil
        eq(arrangementArgs(screens: screens, offsets: nil, blocks: noHz),
           .failure(ArrangeError("no se encontró Odyssey G95C en displayplacer")))
    }
}

func panelStateTests() {
    test("panel payload") {
        let st = TrisplitState(active: 1, configs: [defaultConfig(sortedScreenNames: SORTED_NAMES)], arrange: [:], arrangeOriginal: nil)
        let sorted = sortScreens(LIVE_SCREENS)
        let p = makePanelState(state: st, sortedScreens: sorted, apps: [PanelApp(name: "Finder", count: 2, titles: ["a", "b/c"])],
                               primary: primaryScreen(sorted), hasDisplayplacer: true)
        eq(p.screens.map(\.name), SORTED_NAMES)
        eq(p.screens[2], PanelScreen(name: "Built-in Retina Display", x: 5120, y: 2152, w: 1800, h: 1169), "full frame")
        let js = try panelPushScript(p)
        check(js.hasPrefix("window.trisplitSetState && window.trisplitSetState({"), js)
        check(js.hasSuffix("})"), "ends with })")
        check(js.contains(#""arrange":{}"#), "arrange object")
        check(js.contains(#""hasDisplayplacer":true"#), "hasDisplayplacer")
        check(js.contains(#""axTrusted":true"#), "axTrusted default")
        check(js.contains(#""primary":"Odyssey G95C""#), "primary")
        check(js.contains(#""b/c""#), "slashes unescaped")
        let body = String(js.dropFirst(panelPushPrefix.count).dropLast())
        let j = JSON.parse(body)
        eq(j?["active"], .num(1)); eq(j?["apps"]?.array?.first?["count"], .num(2))
        let p2 = makePanelState(state: st, sortedScreens: [], apps: [], primary: nil, hasDisplayplacer: false)
        check(!(try panelPushScript(p2)).contains("primary"), "nil primary omitted")
        let p3 = makePanelState(state: st, sortedScreens: [], apps: [], primary: nil, hasDisplayplacer: false, axTrusted: false)
        check((try panelPushScript(p3)).contains(#""axTrusted":false"#), "axTrusted false")
    }
}

func coexistenceTests() {
    test("isTrisplitV1Config") {
        let fm = FileManager.default
        let repo = tmpPath("repo")
        try fm.createDirectory(atPath: repo + "/app/Core", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: repo + "/legacy", withIntermediateDirectories: true)
        try "".write(toFile: repo + "/build.sh", atomically: true, encoding: .utf8)
        try "".write(toFile: repo + "/panel.html", atomically: true, encoding: .utf8)
        try "-- v1".write(toFile: repo + "/legacy/init.lua", atomically: true, encoding: .utf8)
        let hs = tmpPath("hs")
        try fm.createDirectory(atPath: hs, withIntermediateDirectories: true)
        let link = hs + "/link.lua"
        try fm.createSymbolicLink(atPath: link, withDestinationPath: repo + "/legacy/init.lua")
        check(isTrisplitV1Config(initLua: link), "symlink into repo")
        let other = tmpPath("other.lua")
        try "-- unrelated".write(toFile: other, atomically: true, encoding: .utf8)
        let link2 = hs + "/link2.lua"
        try fm.createSymbolicLink(atPath: link2, withDestinationPath: other)
        check(!isTrisplitV1Config(initLua: link2), "symlink outside repo")
        let stub = hs + "/stub.lua"
        try "-- trisplit migrated to Trisplit.app (v2)".write(toFile: stub, atomically: true, encoding: .utf8)
        check(!isTrisplitV1Config(initLua: stub), "stub mentioning trisplit")
        let v1 = hs + "/v1.lua"
        try "-- trisplit\nhs.hotkey.bind({'cmd'}, '0', f)".write(toFile: v1, atomically: true, encoding: .utf8)
        check(isTrisplitV1Config(initLua: v1), "hotkey.bind + trisplit")
        let noName = hs + "/other.lua"
        try "hs.hotkey.bind({'cmd'}, '0', f)".write(toFile: noName, atomically: true, encoding: .utf8)
        check(!isTrisplitV1Config(initLua: noName), "hotkey.bind without trisplit")
        check(!isTrisplitV1Config(initLua: hs + "/missing.lua"), "missing")
    }
}
