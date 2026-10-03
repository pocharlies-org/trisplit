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
func gridFrame(_ f: Rect, index i: Int, cols: Int, rows: Int, span: Int = 1) -> Rect {
    let c = max(cols, 1), r = max(rows, 1)
    let w = (f.w - GAP * Double(c - 1)) / Double(c)
    let h = (f.h - GAP * Double(r - 1)) / Double(r)
    let col = flooredMod(i - 1, c)
    let row = flooredDiv(i - 1, c)
    // Clamp so a span never runs past the end of its row.
    let n = Double(min(max(span, 1), c - col))
    return Rect(x: f.x + Double(col) * (w + GAP), y: f.y + Double(row) * (h + GAP), w: n * w + (n - 1) * GAP, h: h)
}

/// Ids of the candidate windows covered by `target`: their frame CENTER lies inside it
/// (inclusive edges). Ids in `keep` and id 0 (unknown window) are never returned.
func windowsCovered(by target: Rect, candidates: [(id: UInt32, frame: Rect)], keep: Set<UInt32>) -> [UInt32] {
    candidates.compactMap { c in
        guard c.id != 0, !keep.contains(c.id) else { return nil }
        let cx = c.frame.x + c.frame.w / 2, cy = c.frame.y + c.frame.h / 2
        let inside = cx >= target.x && cx <= target.x + target.w && cy >= target.y && cy <= target.y + target.h
        return inside ? c.id : nil
    }
}

/// Slot value meaning "continuation of the slot to my left in the same row".
let SPAN_MARK = "<"

/// Columns covered by 1-based slot i: 1 + consecutive SPAN_MARKs to its right in the same row.
/// Returns 0 when slot i is itself a SPAN_MARK. An empty owner spans 1: markers after an
/// empty slot are orphans (see normalizeSpans) and never extend it.
func spanCount(_ slots: [String], index i: Int, cols: Int) -> Int {
    let c = max(cols, 1)
    guard i >= 1 && i <= slots.count else { return 1 }
    if slots[i - 1] == SPAN_MARK { return 0 }
    if slots[i - 1].isEmpty { return 1 }
    var n = 1
    while flooredMod(i - 1 + n, c) != 0, i - 1 + n < slots.count, slots[i - 1 + n] == SPAN_MARK { n += 1 }
    return n
}

/// Orphan SPAN_MARKs (first column of a row, or right of an empty slot) become "".
func normalizeSpans(_ slots: [String], cols: Int) -> [String] {
    let c = max(cols, 1)
    var out = slots
    for k in out.indices where out[k] == SPAN_MARK {
        if k % c == 0 || out[k - 1].isEmpty { out[k] = "" }
    }
    return out
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

/// Order of window ids as slot indexes: ascending id, ties keep input order (stable). Returns input indices.
/// Minimized windows must be part of `ids`, otherwise minimizing renumbers `App#N`.
func slotOrder(ids: [UInt32]) -> [Int] {
    ids.enumerated()
        .sorted { $0.element != $1.element ? $0.element < $1.element : $0.offset < $1.offset }
        .map { $0.offset }
}
