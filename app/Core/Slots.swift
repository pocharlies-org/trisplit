// Slot flattening and the default configuration.
import Foundation

struct FlatSlot: Equatable {
    var screen: String
    var idx: Int
    var cols: Int
    var rows: Int
    var app: String
    var span: Int = 1
}

let DEFAULT_SLOTS: [String: [String]] = ["Odyssey G95C": ["OpenChamber", "Code", "Claude"]]

/// Lua flatSlots(): sorted screens with a monitor in the config, then slot order.
/// SPAN_MARK continuations are skipped (hotkeys address the owner); `span` is the owner's width.
func flatSlots(_ cfg: Config?, sortedScreenNames: [String]) -> [FlatSlot] {
    guard let cfg else { return [] }
    var out: [FlatSlot] = []
    for name in sortedScreenNames {
        guard let m = cfg.monitors[name] else { continue }
        for (i, app) in m.slots.enumerated() where app != SPAN_MARK {
            out.append(FlatSlot(screen: name, idx: i + 1, cols: m.cols, rows: m.rows, app: app,
                                span: spanCount(m.slots, index: i + 1, cols: m.cols)))
        }
    }
    return out
}

/// Lua defaultConfig(): "Dev", a 3x1 grid per screen, Odyssey G95C prefilled.
func defaultConfig(sortedScreenNames: [String]) -> Config {
    var monitors: [String: MonitorGrid] = [:]
    for name in sortedScreenNames {
        var g = newMonitorGrid(cols: 3, rows: 1)
        for (i, app) in (DEFAULT_SLOTS[name] ?? []).enumerated() where i < g.slots.count {
            g.slots[i] = app
        }
        monitors[name] = g
    }
    return Config(name: "Dev", monitors: monitors)
}

/// Lua cycle for ⌘⌥⇧0: active % count + 1.
func nextActive(_ active: Int, count: Int) -> Int {
    guard count > 0 else { return active }
    return flooredMod(active, count) + 1
}
