import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The panes in the sidebar. Titles and text are Turkish (user-facing).
enum Pane: String, CaseIterable, Identifiable {
    case general, corners, buttons, titlebar, border, apps, status, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .corners: "Corners"
        case .buttons: "Buttons"
        case .titlebar: "Title Bar"
        case .border: "Border"
        case .apps: "App Rules"
        case .status: "Status"
        case .about: "About"
        }
    }

    /// WhiteSur icon theme artwork in Resources/Icons (GPL-3.0, see assets/WHITESUR-ICONS-GPL-3.0.txt).
    var iconName: String { rawValue }

    var summary: String {
        switch self {
        case .general: "Turn MacTweak on or off, start it at login, and reach every settings pane from here."
        case .corners: "Choose how round window corners are. Changes apply to open windows right away."
        case .buttons: "Choose how the close, minimize and zoom buttons look."
        case .titlebar: "Traffic light placement and spacing, and title bar metrics for apps built with an SDK older than macOS 26."
        case .border: "A colored border around windows, fading of background windows, and window shadows."
        case .apps: "Exclude an app from MacTweak or give it its own corner radius."
        case .status: "System security settings, the background agent, and MacTweak's state in open apps."
        case .about: "Version, privacy, and what to do if something goes wrong."
        }
    }
}

// MARK: - General

struct GeneralPane: View {
    let open: (Pane) -> Void
    @AppStorage(Key.enabled) private var enabled = true
    @AppStorage(Key.cornerStyle) private var cornerStyle = "sequoia"
    @AppStorage(Key.buttonTheme) private var buttonTheme = 0
    @AppStorage(Key.keepOnTop) private var keepOnTop = false
    @AppStorage(Key.restartFinderAtLogin) private var restartFinder = true
    @State private var agentInstalled = SystemControl.agentInstalled
    @State private var agentRunning = Notify.agentRunning
    @State private var error: String?
    @StateObject private var rules = AppRules()

    var body: some View {
        Form {
            PaneHeader(pane: .general)
            if !agentInstalled {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "power.circle.fill").font(.title).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MacTweak is not running").font(.headline)
                            Text("Once started, it applies to apps you open from then on.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Start") { setAgent(true) }.buttonStyle(.borderedProminent)
                    }
                }
            }
            Section {
                Toggle("Enable MacTweak", isOn: $enabled)
                Toggle("Start at login", isOn: Binding(get: { agentInstalled }, set: { setAgent($0) }))
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }
            Section {
                NavigationRow(pane: .corners, value: CornerStyle.named(cornerStyle), open: open)
                NavigationRow(pane: .buttons, value: ButtonTheme.named(buttonTheme), open: open)
                NavigationRow(pane: .titlebar, open: open)
            }
            Section {
                NavigationRow(pane: .apps, value: rules.rules.isEmpty ? "" : "\(rules.rules.count) rules", open: open)
                NavigationRow(pane: .status, value: agentRunning ? "Running" : "Not running", open: open)
                NavigationRow(pane: .about, open: open)
            }
            Section("Other") {
                Toggle(isOn: $restartFinder) {
                    Text("Restart Finder at login")
                    Text("If Finder starts before MacTweak, it is restarted once.")
                }
                Toggle("Keep this window on top", isOn: $keepOnTop)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            rules.load()
            agentRunning = Notify.agentRunning
        }
    }

    private func setAgent(_ on: Bool) {
        do {
            if on { try SystemControl.installAgent() } else { SystemControl.uninstallAgent() }
            error = nil
        } catch {
            self.error = "Could not start: \(error.localizedDescription)"
        }
        agentInstalled = SystemControl.agentInstalled
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { agentRunning = Notify.agentRunning }
    }
}

// MARK: - Corners

struct CornersPane: View {
    @AppStorage(Key.cornerStyle) private var cornerStyle = "sequoia"
    @AppStorage(Key.customTop) private var customTop = 10.0
    @AppStorage(Key.customBottom) private var customBottom = 10.0
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    var body: some View {
        Form {
            PaneHeader(pane: .corners)
            Section("Corner style") {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(CornerStyle.all) { s in
                        let r = radius(s)
                        StyleCard(style: s, top: r.top, bottom: r.bottom, selected: cornerStyle == s.id)
                            .onTapGesture { cornerStyle = s.id }
                    }
                }
                .padding(.vertical, 6)
            }
            if cornerStyle == "custom" {
                Section("Custom radius") {
                    RadiusSlider(title: "Top corners", value: $customTop)
                    RadiusSlider(title: "Bottom corners", value: $customBottom)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func radius(_ s: CornerStyle) -> (top: Double, bottom: Double) {
        switch s.id {
        case "system": (CornerStyle.systemRadius, CornerStyle.systemRadius)
        case "custom": (customTop, customBottom)
        default: (s.top ?? 10, s.bottom ?? 10)
        }
    }
}

// MARK: - Buttons

struct ButtonsPane: View {
    @AppStorage(Key.buttonTheme) private var theme = 0
    @AppStorage(Key.inactiveButtonColor) private var inactiveColor = false
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    var body: some View {
        Form {
            PaneHeader(pane: .buttons)
            themeSection("Built in", footer: "Drawn by MacTweak. Hover over a card to see the symbols.", source: .builtIn)
            themeSection("From open-source themes", footer: "Button artwork from GTK themes: Arc, Graphite, Orchis, Colloid, WhiteSur and Fluent.", source: .openSource)
            themeSection("KDE favorites", footer: "The most downloaded window decorations on the KDE Store, with their own artwork.", source: .kde)
            Section {
                Toggle(isOn: $inactiveColor) {
                    Text("Keep colors in background windows")
                    Text("macOS turns a background window's buttons gray.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func themeSection(_ title: String, footer: String, source: ButtonTheme.Source) -> some View {
        Section {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(ButtonTheme.all.filter { $0.source == source }) { t in
                    ThemeCard(theme: t, selected: theme == t.id).onTapGesture { theme = t.id }
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }
}

// MARK: - Title bar

struct TitlebarPane: View {
    @AppStorage(Key.indentTrafficLights) private var indent = false
    @AppStorage(Key.legacyTitlebarHeight) private var legacyHeight = false
    @AppStorage(Key.legacyButtonSpacing) private var legacySpacing = false
    @AppStorage(Key.buttonSpacing) private var spacing = 0.0

    var body: some View {
        Form {
            PaneHeader(pane: .titlebar)
            Section("Traffic lights") {
                LabeledContent("Spacing") {
                    HStack {
                        Slider(value: $spacing, in: -6...12, step: 1)
                        Text(spacing == 0 ? "System" : String(format: "%+.0f pt", spacing))
                            .monospacedDigit().frame(width: 62, alignment: .trailing)
                        Button("Reset") { spacing = 0 }.disabled(spacing == 0)
                    }
                }
                Toggle(isOn: $indent) {
                    Text("Indent and center")
                    Text("In windows without a toolbar, moves the buttons away from the edge and centers them in the title bar.")
                }
            }
            Section {
                Toggle(isOn: $legacyHeight) {
                    Text("Modern title bar height")
                    Text("The title bar becomes 32 pt instead of 28.")
                }
                Toggle(isOn: $legacySpacing) {
                    Text("Modern button spacing")
                    Text("Buttons are 23 pt apart instead of 20.")
                }
            } header: {
                Text("Legacy apps")
            } footer: {
                Text("Apps built with an SDK older than macOS 26 (e.g. Muxy, Zed, VLC) use the old metrics. Changes show after the app is reopened.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Border

struct BorderPane: View {
    @AppStorage(Key.borderEnabled) private var enabled = false
    @AppStorage(Key.borderWidth) private var width = 2.0
    @AppStorage(Key.borderColor) private var colorHex = "#E2A100FF"
    @AppStorage(Key.borderActiveOnly) private var activeOnly = true
    @AppStorage(Key.inactiveOpacity) private var inactiveOpacity = 100.0
    @AppStorage(Key.windowShadow) private var shadow = true

    private let presets = ["#E2A100FF", "#17191CFF", "#8E8E93FF", "#FF5F57FF", "#0A84FFFF", "#28C840FF", "#BF5AF2FF"]

    var body: some View {
        Form {
            PaneHeader(pane: .border)
            Section {
                HStack(spacing: 24) {
                    BorderPreview(color: Color(hex: colorHex), width: enabled ? width : 0, shadow: shadow, dimmed: false)
                    if !activeOnly || inactiveOpacity < 100 {
                        BorderPreview(color: Color(hex: colorHex), width: enabled && !activeOnly ? width : 0, shadow: shadow,
                                      dimmed: true, opacity: inactiveOpacity / 100)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Border") {
                Toggle("Show a border around windows", isOn: $enabled)
                Picker("Show on", selection: $activeOnly) {
                    Text("Active window only").tag(true)
                    Text("All windows").tag(false)
                }
                .disabled(!enabled)
                LabeledContent("Width") {
                    HStack {
                        Slider(value: $width, in: 0.5...8, step: 0.5)
                        Text(String(format: "%.1f pt", width)).monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                .disabled(!enabled)
                LabeledContent("Color") {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(colorHex == hex ? 0.9 : 0.15), lineWidth: colorHex == hex ? 2 : 1))
                                .onTapGesture { colorHex = hex }
                                .help(hex)
                        }
                        ColorPicker("", selection: Binding(get: { Color(hex: colorHex) }, set: { colorHex = $0.hexRGBA }), supportsOpacity: true)
                            .labelsHidden()
                    }
                }
                .disabled(!enabled)
            }
            Section {
                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: $inactiveOpacity, in: 40...100, step: 5)
                        Text(inactiveOpacity >= 100 ? "Off" : String(format: "%.0f%%", inactiveOpacity))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Background windows")
            } footer: {
                Text("Windows you are not using fade, so the active one stands out.")
            }
            Section("Shadow") {
                Toggle("Window shadows", isOn: $shadow)
            }
        }
        .formStyle(.grouped)
    }
}

/// Small window drawing for the Border pane.
struct BorderPreview: View {
    let color: Color
    let width: Double
    let shadow: Bool
    let dimmed: Bool
    var opacity: Double = 1

    var body: some View {
        VStack(spacing: 6) {
            MiniWindow(top: 10, bottom: 10)
                .frame(width: 150, height: 94)
                .overlay(RoundedRectangle(cornerRadius: 6.2, style: .continuous).strokeBorder(color, lineWidth: width * 0.62))
                .shadow(color: .black.opacity(shadow ? 0.18 : 0), radius: 8, y: 4)
                .opacity(dimmed ? opacity : 1)
            Text(dimmed ? "Background window" : "Active window").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - App rules

struct AppRulesPane: View {
    @StateObject private var model = AppRules()

    var body: some View {
        Form {
            PaneHeader(pane: .apps)
            Section {
                ForEach($model.rules) { $rule in
                    RuleRow(rule: $rule, changed: model.save, remove: { model.remove(rule.id) })
                }
                Button("Add App…", systemImage: "plus", action: chooseApps)
            } header: {
                Text("Rules")
            } footer: {
                Text("Changes apply to open windows right away.")
            }
            if !model.automatic.isEmpty {
                Section {
                    ForEach(model.automatic) { a in
                        HStack(spacing: 10) {
                            Image(nsImage: InstalledApps.icon(a.id)).resizable().frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name)
                                Text("\(a.reason) \(a.date)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Yeniden Dene") { model.removeAutomatic(a.id) }
                        }
                    }
                } header: {
                    Text("Excluded automatically")
                } footer: {
                    Text("Apps that crashed while MacTweak was loaded end up here.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.load() }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { model.add(id) }
        }
    }
}

struct RuleRow: View {
    @Binding var rule: AppRule
    let changed: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: rule.icon).resizable().frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.name)
                    Text(rule.id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $rule.kind) {
                    ForEach(AppRule.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: rule.kind) { changed() }
                Button(role: .destructive, action: remove) { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Remove rule")
            }
            if rule.kind == .customRadius {
                RadiusSlider(title: "Top", value: $rule.top).onChange(of: rule.top) { changed() }
                RadiusSlider(title: "Bottom", value: $rule.bottom).onChange(of: rule.bottom) { changed() }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Status

struct StatusInfo: Sendable {
    var sip = false, amfi = false, fileVault = false, agent = false, environment = false, liquidRadius = false

    static func read() -> StatusInfo {
        StatusInfo(sip: SystemControl.sipDisabled, amfi: SystemControl.amfiDisabled, fileVault: SystemControl.fileVaultOn,
                   agent: Notify.agentRunning, environment: SystemControl.inEnvironment,
                   liquidRadius: SystemControl.liquidRadiusActive)
    }
}

struct StatusPane: View {
    @State private var info = StatusInfo()
    @State private var apps: [NSRunningApplication] = []
    @State private var relaunching: Set<pid_t> = []

    var body: some View {
        Form {
            PaneHeader(pane: .status)
            Section {
                StatusRow(title: "System Integrity Protection (SIP)", ok: info.sip, yes: "Off", no: "On", relaxed: true,
                          info: "Must be off so MacTweak can load into other apps. It can only be changed in Recovery Mode.")
                StatusRow(title: "AMFI checks", ok: info.amfi, yes: "Off", no: "On", relaxed: true,
                          info: "Must be off so the library can load into signed apps (boot-args).")
                StatusRow(title: "FileVault", ok: info.fileVault, yes: "On", no: "Off",
                          info: "Disk encryption. Unrelated to MacTweak; keeping it on is recommended.")
            } header: {
                Text("System")
            } footer: {
                Text("Turning SIP and AMFI off relaxes one of macOS's defences. MacTweak needs no root access and loads no code into system processes; it only loads into apps you open.")
            }
            Section("MacTweak") {
                StatusRow(title: "Background agent", ok: info.agent, yes: "Running", no: "Not running")
                StatusRow(title: "Loading into new apps", ok: info.environment, yes: "On", no: "Off")
                if info.liquidRadius {
                    Label("Liquid Radius is still active. Both tools hook the same places; turn one off.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                ForEach(apps, id: \.processIdentifier) { app in
                    HStack(spacing: 10) {
                        if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                        Text(app.localizedName ?? app.bundleIdentifier ?? "?")
                        Spacer()
                        switch SystemControl.loadState(app.processIdentifier) {
                        case .active: Text("Active").foregroundStyle(.green)
                        case .outdated:
                            if relaunching.contains(app.processIdentifier) {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Outdated").foregroundStyle(.orange)
                                Button("Relaunch") { relaunch(app) }
                            }
                        case .inert: Text("System window").foregroundStyle(.secondary)
                        case .missing:
                            if relaunching.contains(app.processIdentifier) {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Relaunch") { relaunch(app) }.disabled(!info.environment)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Open apps")
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise", action: load)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            } footer: {
                Text("MacTweak loads into apps opened after the agent started. Apps opened before, or before the last MacTweak update, keep the old behavior until they are relaunched.")
            }
        }
        .formStyle(.grouped)
        .task { load() }
    }

    private func load() {
        Task {
            info = await Task.detached { StatusInfo.read() }.value
            apps = SystemControl.runningApps
        }
    }

    private func relaunch(_ app: NSRunningApplication) {
        relaunching.insert(app.processIdentifier)
        Task {
            await SystemControl.relaunch(app)
            try? await Task.sleep(for: .seconds(1.5))
            relaunching.remove(app.processIdentifier)
            load()
        }
    }
}

// MARK: - About

struct AboutPane: View {
    @State private var confirmRemove = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                    Text("MacTweak").font(.title2.bold())
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                        .foregroundStyle(.secondary)
                    Text("Tweak macOS 27 windows your way: corners, buttons, title bar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            Section {
                LabeledContent("Data collection", value: "None, it makes no network connections")
                LabeledContent("Root access", value: "Not needed")
                LabeledContent("Crash protection", value: "Excludes an app that crashes")
            }
            Section {
                Text("If an app won't open, exclude it in App Rules. If nothing opens, start your Mac in Safe Mode (login agents don't run) and remove MacTweak.")
                    .foregroundStyle(.secondary)
                Button("Remove MacTweak…", role: .destructive) { confirmRemove = true }
            } header: {
                Text("If something goes wrong")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove MacTweak?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                SystemControl.removeEverything()
                NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in NSApp.terminate(nil) }
            }
        } message: {
            Text("The agent stops, open windows return to the default, and the app moves to the Trash. Preferences are kept.")
        }
    }
}
