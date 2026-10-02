// Persistent state model: {active, configs:[{name, monitors}], arrange, arrangeOriginal}.
import Foundation

struct MonitorGrid: Encodable, Equatable {
    var cols: Int
    var rows: Int
    var slots: [String]

    static func from(_ j: JSON) -> MonitorGrid? {
        guard let o = j.object else { return nil }
        let slots = (o["slots"]?.array ?? []).map { $0.string ?? "" }
        let cols = o["cols"]?.int ?? 1
        return MonitorGrid(cols: cols, rows: o["rows"]?.int ?? 1, slots: normalizeSpans(slots, cols: cols))
    }
}

func newMonitorGrid(cols: Int, rows: Int) -> MonitorGrid {
    MonitorGrid(cols: cols, rows: rows, slots: Array(repeating: "", count: max(cols * rows, 0)))
}

struct Config: Encodable, Equatable {
    var name: String
    var monitors: [String: MonitorGrid]

    /// Lenient decode + Lua migrate(): legacy `slots:[{screen,app}]` without `monitors`
    /// becomes one 3x1 grid per screen with the apps appended in order.
    static func from(_ j: JSON) -> Config? {
        guard let o = j.object else { return nil }
        var monitors: [String: MonitorGrid] = [:]
        if let m = o["monitors"], m != .null {
            for (k, v) in m.object ?? [:] {
                if let g = MonitorGrid.from(v) { monitors[k] = g }
            }
        } else {
            for sl in o["slots"]?.array ?? [] {
                guard let screen = sl["screen"]?.string else { continue }
                var g = monitors[screen] ?? MonitorGrid(cols: 3, rows: 1, slots: [])
                g.slots.append(sl["app"]?.string ?? "")
                monitors[screen] = g
            }
        }
        return Config(name: o["name"]?.string ?? "", monitors: monitors)
    }
}

struct Offset: Encodable, Equatable {
    var dx: Double
    var dy: Double
}

func offsetsFrom(_ j: JSON?) -> [String: Offset] {
    var out: [String: Offset] = [:]
    for (k, v) in j?.object ?? [:] {
        if let dx = v["dx"]?.number, let dy = v["dy"]?.number { out[k] = Offset(dx: dx, dy: dy) }
    }
    return out
}

struct TrisplitState: Encodable, Equatable {
    var active: Int
    var configs: [Config]
    var arrange: [String: Offset]
    var arrangeOriginal: [String: Offset]?

    var activeConfig: Config? {
        (active >= 1 && active <= configs.count) ? configs[active - 1] : nil
    }

    /// nil unless it is an object with at least one config (Lua loadState).
    static func from(_ j: JSON) -> TrisplitState? {
        guard j.object != nil else { return nil }
        let configs = (j["configs"]?.array ?? []).compactMap(Config.from)
        guard !configs.isEmpty else { return nil }
        var s = TrisplitState(active: j["active"]?.int ?? 1, configs: configs,
                              arrange: offsetsFrom(j["arrange"]), arrangeOriginal: nil)
        if let ao = j["arrangeOriginal"], ao != .null { s.arrangeOriginal = offsetsFrom(ao) }
        s.normalizeActive()
        return s
    }

    mutating func normalizeActive() {
        if active < 1 || active > configs.count { active = 1 }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(active, forKey: .active)
        try c.encode(configs, forKey: .configs)
        try c.encode(arrange, forKey: .arrange)
        try c.encodeIfPresent(arrangeOriginal, forKey: .arrangeOriginal)
    }
    private enum K: String, CodingKey { case active, configs, arrange, arrangeOriginal }
}

// MARK: - Paths and persistence

func legacyStatePath(home: String) -> String {
    home + "/.hammerspoon/trisplit.json"
}

func defaultStatePath(home: String) -> String {
    home + "/Library/Application Support/trisplit/trisplit.json"
}

/// TRISPLIT_STATE (tests) overrides the real location.
func resolveStatePath(env: [String: String], home: String) -> (path: String, overridden: Bool) {
    if let p = env["TRISPLIT_STATE"], !p.isEmpty { return (p, true) }
    return (defaultStatePath(home: home), false)
}

/// Copies the Hammerspoon-era file to the new location once. Never modifies the old one.
@discardableResult
func importLegacyIfNeeded(newPath: String, legacyPath: String) -> Bool {
    let fm = FileManager.default
    guard !fm.fileExists(atPath: newPath), fm.fileExists(atPath: legacyPath) else { return false }
    do {
        try fm.createDirectory(atPath: (newPath as NSString).deletingLastPathComponent,
                               withIntermediateDirectories: true)
        try fm.copyItem(atPath: legacyPath, toPath: newPath)
        return true
    } catch {
        return false
    }
}

func saveState(_ s: TrisplitState, path: String) throws {
    try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                            withIntermediateDirectories: true)
    try encodeJSON(s).write(to: URL(fileURLWithPath: path), options: .atomic)
}

struct LoadResult {
    var state: TrisplitState
    var usedDefault: Bool
    var backupPath: String?
}

/// Lua loadState(): keep the file only if it has configs; otherwise save a default.
/// An unreadable existing file is copied to `<path>.corrupt-<ts>` before being replaced.
func loadState(path: String, defaultConfig: () -> Config, now: Date = Date()) -> LoadResult {
    let fm = FileManager.default
    if let data = fm.contents(atPath: path), let j = JSON.parse(data), let s = TrisplitState.from(j) {
        return LoadResult(state: s, usedDefault: false, backupPath: nil)
    }
    var backup: String?
    if fm.fileExists(atPath: path) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let b = "\(path).corrupt-\(f.string(from: now))"
        if (try? fm.copyItem(atPath: path, toPath: b)) != nil { backup = b }
    }
    let s = TrisplitState(active: 1, configs: [defaultConfig()], arrange: [:], arrangeOriginal: nil)
    try? saveState(s, path: path)
    return LoadResult(state: s, usedDefault: true, backupPath: backup)
}
