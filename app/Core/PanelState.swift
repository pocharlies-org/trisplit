// Payload pushed to panel.html via window.trisplitSetState(...).
import Foundation

struct PanelScreen: Encodable, Equatable {
    var name: String
    var x, y, w, h: Double
}

struct PanelApp: Encodable, Equatable {
    var name: String
    var count: Int
    var titles: [String]
    var minimized: [Bool] = []
}

struct PanelState: Encodable {
    var screens: [PanelScreen]
    var configs: [Config]
    var active: Int
    var apps: [PanelApp]
    var primary: String?
    var arrange: [String: Offset]
    var hasDisplayplacer: Bool
    var axTrusted: Bool = true

    private enum K: String, CodingKey {
        case screens, configs, active, apps, primary, arrange, hasDisplayplacer, axTrusted
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        try c.encode(screens, forKey: .screens)
        try c.encode(configs, forKey: .configs)
        try c.encode(active, forKey: .active)
        try c.encode(apps, forKey: .apps)
        try c.encodeIfPresent(primary, forKey: .primary)
        try c.encode(arrange, forKey: .arrange)
        try c.encode(hasDisplayplacer, forKey: .hasDisplayplacer)
        try c.encode(axTrusted, forKey: .axTrusted)
    }
}

/// Lua panelState(): sorted screens with full frames, current state, visible apps.
func makePanelState(state: TrisplitState, sortedScreens: [ScreenInfo], apps: [PanelApp],
                    primary: String?, hasDisplayplacer: Bool, axTrusted: Bool = true) -> PanelState {
    PanelState(
        screens: sortedScreens.map {
            PanelScreen(name: $0.name, x: $0.full.x, y: $0.full.y, w: $0.full.w, h: $0.full.h)
        },
        configs: state.configs, active: state.active, apps: apps, primary: primary,
        arrange: state.arrange, hasDisplayplacer: hasDisplayplacer, axTrusted: axTrusted)
}

/// Lua visibleApps() ordering: by string.lower (ASCII) name.
func sortApps(_ apps: [PanelApp]) -> [PanelApp] {
    apps.enumerated().sorted { a, b in
        let la = asciiLower(a.element.name), lb = asciiLower(b.element.name)
        return la != lb ? la < lb : a.offset < b.offset
    }.map { $0.element }
}

/// Guarded so an early push (page not loaded yet) is a no-op instead of a TypeError.
let panelPushPrefix = "window.trisplitSetState && window.trisplitSetState("

func panelPushScript(_ p: PanelState) throws -> String {
    "\(panelPushPrefix)\(try encodeJSONString(p)))"
}
