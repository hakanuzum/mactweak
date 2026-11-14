import AppKit
import SwiftUI

/// Preference keys. mactweak-agent (agent/agent.m) reads the same keys.
enum Key {
    static let enabled = "enabled"
    static let cornerStyle = "cornerStyle"
    static let customTop = "customTop"
    static let customBottom = "customBottom"
    static let indentTrafficLights = "indentTrafficLights"
    static let legacyTitlebarHeight = "legacyTitlebarHeight"
    static let legacyButtonSpacing = "legacyButtonSpacing"
    static let buttonTheme = "buttonTheme"
    static let inactiveButtonColor = "inactiveButtonColor"
    static let excludedApps = "excludedApps"
    static let customRadii = "customRadii"
    static let autoExcludedApps = "autoExcludedApps"
    static let restartFinderAtLogin = "restartFinderAtLogin"
    static let keepOnTop = "keepOnTop"
}

enum Notify {
    static let domain = "dev.hakanuzum.mactweak"
    static let settings = domain + ".settings"
    static let reload = domain + ".reload"
    static let alivePrefix = domain + ".alive."

    static func reloadAgent() { notify_post(reload) }

    static func state(_ name: String) -> UInt64 {
        var token: Int32 = 0
        var value: UInt64 = 0
        guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { return 0 }
        notify_get_state(token, &value)
        notify_cancel(token)
        return value
    }

    /// Is the agent running? (the global state carries the magic byte)
    static var agentRunning: Bool { state(settings) & 0xFF == 0x4B }
}

// MARK: - Corner styles

struct CornerStyle: Identifiable, Hashable {
    let id: String
    let name: String
    let top: Double?  // nil: macOS default / custom
    let bottom: Double?

    static let all: [CornerStyle] = [
        CornerStyle(id: "system", name: "macOS 27", top: nil, bottom: nil),
        CornerStyle(id: "medium", name: "Medium", top: 13, bottom: 13),
        CornerStyle(id: "sequoia", name: "Sequoia", top: 10, bottom: 10),
        CornerStyle(id: "catalina", name: "Catalina", top: 5, bottom: 0),
        CornerStyle(id: "square", name: "Square", top: 0, bottom: 0),
        CornerStyle(id: "custom", name: "Custom", top: nil, bottom: nil),
    ]
    static let systemRadius = 16.0  // measured default on macOS 27

    static func named(_ id: String) -> String { all.first { $0.id == id }?.name ?? id }
}

// MARK: - Button themes (same order and colors as core/buttons.m)

struct ButtonTheme: Identifiable, Hashable {
    let id: Int
    let name: String
    var folder: String? = nil  // image theme: Resources/ButtonThemes/<folder>

    /// Image of an image theme's button (index 0 close, 1 minimize, 2 zoom) in a state.
    static func image(theme: Int, index: Int, hovering: Bool) -> NSImage? {
        guard let folder = all.first(where: { $0.id == theme })?.folder else { return nil }
        let button = ["close", "min", "max"][index]
        let url = Bundle.main.url(forResource: "\(button)-\(hovering ? "hover" : "normal")", withExtension: "png",
                                  subdirectory: "ButtonThemes/\(folder)")
        return url.flatMap(NSImage.init(contentsOf:))
    }

    static let all: [ButtonTheme] = [
        ButtonTheme(id: 0, name: "System"),
        ButtonTheme(id: 1, name: "Classic"),
        ButtonTheme(id: 2, name: "Square"),
        ButtonTheme(id: 3, name: "Ring"),
        ButtonTheme(id: 4, name: "Graphite"),
        ButtonTheme(id: 5, name: "Dot"),
        ButtonTheme(id: 6, name: "Pastel"),
        ButtonTheme(id: 7, name: "Aqua"),
        ButtonTheme(id: 8, name: "Platinum"),
        ButtonTheme(id: 9, name: "Black"),
        ButtonTheme(id: 10, name: "Symbols"),
        ButtonTheme(id: 11, name: "Capsule"),
        ButtonTheme(id: 12, name: "Neon"),
        // Image themes from open-source GTK/xfwm4 themes (assets/button-themes)
        ButtonTheme(id: 32, name: "Arc", folder: "arc"),
        ButtonTheme(id: 33, name: "Glyph", folder: "graphite"),
        ButtonTheme(id: 34, name: "Orchis", folder: "orchis"),
        ButtonTheme(id: 35, name: "Colloid", folder: "colloid"),
        ButtonTheme(id: 36, name: "Nord", folder: "nord"),
        ButtonTheme(id: 37, name: "Fluent", folder: "fluent-square"),
    ]

    static func named(_ id: Int) -> String { all.first { $0.id == id }?.name ?? "System" }

    static func color(theme: Int, index: Int) -> Color {
        switch theme {
        case 4: return Color(red: 0.557, green: 0.557, blue: 0.576)
        case 9: return Color(red: 0.14, green: 0.14, blue: 0.15)
        case 10: return Color(red: 0.45, green: 0.45, blue: 0.47)
        case 6: return [Color(red: 0.957, green: 0.651, blue: 0.627), Color(red: 0.965, green: 0.835, blue: 0.557),
                        Color(red: 0.659, green: 0.867, blue: 0.647)][index]
        default: return [Color(red: 1.0, green: 0.373, blue: 0.341), Color(red: 0.996, green: 0.737, blue: 0.180),
                         Color(red: 0.157, green: 0.784, blue: 0.251)][index]
        }
    }
}

// MARK: - Per-app rules

struct AppRule: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case exclude = "Exclude"
        case customRadius = "Custom corners"
        var id: String { rawValue }
    }

    let id: String  // bundle identifier
    var kind: Kind
    var top: Double
    var bottom: Double

    var name: String { InstalledApps.name(id) }
    var icon: NSImage { InstalledApps.icon(id) }
}

enum InstalledApps {
    static func url(_ bundleID: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    static func name(_ bundleID: String) -> String {
        guard let u = url(bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(_ bundleID: String) -> NSImage {
        guard let u = url(bundleID) else { return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)! }
        return NSWorkspace.shared.icon(forFile: u.path)
    }
}

struct AutoExclusion: Identifiable {
    let id: String
    let name: String
    let reason: String
    let date: String
}

/// Reads and writes the rule list (excludedApps + customRadii) in preferences.
@MainActor
final class AppRules: ObservableObject {
    @Published var rules: [AppRule] = []
    @Published var automatic: [AutoExclusion] = []
    private let defaults = UserDefaults.standard

    init() { load() }

    func load() {
        var list: [AppRule] = []
        for id in defaults.stringArray(forKey: Key.excludedApps) ?? [] {
            list.append(AppRule(id: id, kind: .exclude, top: 10, bottom: 10))
        }
        let custom = defaults.dictionary(forKey: Key.customRadii) as? [String: [String: Double]] ?? [:]
        for (id, v) in custom where !list.contains(where: { $0.id == id }) {
            list.append(AppRule(id: id, kind: .customRadius, top: v["top"] ?? 10, bottom: v["bottom"] ?? 10))
        }
        rules = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let auto = defaults.dictionary(forKey: Key.autoExcludedApps) as? [String: [String: String]] ?? [:]
        automatic = auto.map { AutoExclusion(id: $0.key, name: $0.value["name"] ?? $0.key, reason: $0.value["reason"] ?? "",
                                             date: $0.value["date"] ?? "") }
            .sorted { $0.name < $1.name }
    }

    func save() {
        defaults.set(rules.filter { $0.kind == .exclude }.map(\.id), forKey: Key.excludedApps)
        var custom: [String: [String: Double]] = [:]
        for r in rules where r.kind == .customRadius { custom[r.id] = ["top": r.top, "bottom": r.bottom] }
        defaults.set(custom, forKey: Key.customRadii)
        Notify.reloadAgent()
    }

    func add(_ bundleID: String) {
        guard !rules.contains(where: { $0.id == bundleID }) else { return }
        rules.append(AppRule(id: bundleID, kind: .exclude, top: 10, bottom: 10))
        save()
    }

    func remove(_ bundleID: String) {
        rules.removeAll { $0.id == bundleID }
        save()
    }

    func removeAutomatic(_ bundleID: String) {
        var auto = defaults.dictionary(forKey: Key.autoExcludedApps) ?? [:]
        auto.removeValue(forKey: bundleID)
        defaults.set(auto, forKey: Key.autoExcludedApps)
        Notify.reloadAgent()
        load()
    }
}
