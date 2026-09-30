// Pure layout math shared by the app and the unit tests (no AppKit).
// Coordinates are always global top-left (y grows downwards), like Hammerspoon.
import Foundation

struct Rect: Equatable, Codable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

let GAP = 4.0

/// Lua `a % b` is a floored modulo; keep that for any sign.
func flooredMod(_ a: Int, _ b: Int) -> Int {
    let r = a % b
    return (r != 0 && (r < 0) != (b < 0)) ? r + b : r
}

func flooredDiv(_ a: Int, _ b: Int) -> Int {
    Int((Double(a) / Double(b)).rounded(.down))
}

/// Slot `index` (1-based) of a cols×rows grid inside `f` (the screen's visible frame).
func gridFrame(_ f: Rect, index i: Int, cols: Int, rows: Int) -> Rect {
    let c = max(cols, 1), r = max(rows, 1)
    let w = (f.w - GAP * Double(c - 1)) / Double(c)
    let h = (f.h - GAP * Double(r - 1)) / Double(r)
    let col = flooredMod(i - 1, c)
    let row = flooredDiv(i - 1, c)
    return Rect(x: f.x + Double(col) * (w + GAP), y: f.y + Double(row) * (h + GAP), w: w, h: h)
}

/// "App#N" = N-th window of App. Mirrors Lua `^(.-)#(%d+)$`: the last `#` followed
/// by a non-empty run of ASCII digits up to the end; anything else is (spec, 1).
func parseSpec(_ spec: String) -> (name: String, idx: Int) {
    guard let hash = spec.lastIndex(of: "#") else { return (spec, 1) }
    let suffix = spec[spec.index(after: hash)...]
    guard !suffix.isEmpty, suffix.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) else {
        return (spec, 1)
    }
    return (String(spec[..<hash]), Int(suffix) ?? Int.max)
}

/// Spec persisted by moveFrontToSlot: bare app name for the first window, `app#idx` otherwise.
func slotSpec(app: String, idx: Int) -> String {
    idx > 1 ? "\(app)#\(idx)" : app
}

/// Lua `wins[math.min(idx, #wins)]` with 1-based idx; nil when out of range (idx < 1 or empty).
func pickWindow<T>(_ wins: [T], idx: Int) -> T? {
    let i = min(idx, wins.count)
    return (i >= 1 && i <= wins.count) ? wins[i - 1] : nil
}

/// Per-window slot winners for one applyConfig run. `targets[i]` is job i's resolved window id
/// (0 = unresolved) and whether its index was exact (N <= window count) or clamped. When several
/// jobs hit the same window, an exact job beats a clamped one and among ties the LAST job wins
/// (`Code#2` clamped onto `Code`'s only window must not steal it). Id 0 is never deduped.
/// Returns the indices of the jobs that keep their window.
func slotWinners(_ targets: [(id: Int, exact: Bool)]) -> Set<Int> {
    var keep = Set<Int>()
    var best: [Int: Int] = [:]  // window id -> winning job index
    for (i, t) in targets.enumerated() {
        if t.id == 0 { keep.insert(i); continue }
        if let b = best[t.id], targets[b].exact && !t.exact { continue }
        best[t.id] = i
    }
    keep.formUnion(best.values)
    return keep
}

/// math.floor to Int, nil for NaN/inf/absurd values (avoids Int() traps).
func floorInt(_ d: Double) -> Int? {
    guard d.isFinite, abs(d) < 1e15 else { return nil }
    return Int(d.rounded(.down))
}
