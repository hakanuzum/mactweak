import AppKit
import SwiftUI

@main
struct MacTweakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("MacTweak", id: "main") {
            RootView().frame(minWidth: 760, minHeight: 540)
        }
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observer: NSObjectProtocol?
    private var pending: DispatchWorkItem?

    func applicationDidFinishLaunching(_ n: Notification) {
        // Tell the agent about every preference change (coalesced while a slider is dragged).
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.pending?.cancel()
            let work = DispatchWorkItem { Notify.reloadAgent() }
            self?.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

/// Sidebar + detail, laid out like System Settings: search field, an account-style
/// row at the top, grouped sections, and back/forward buttons in the toolbar.
struct RootView: View {
    @State private var selection: Pane? = .general
    @State private var history: [Pane] = [.general]
    @State private var position = 0
    @State private var navigatingHistory = false
    @State private var search = ""
    @AppStorage(Key.keepOnTop) private var keepOnTop = false
    @AppStorage(Key.enabled) private var enabled = true

    private let groups: [[Pane]] = [[.general], [.corners, .buttons, .titlebar], [.apps, .status]]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if search.isEmpty {
                    AccountRow(enabled: enabled).tag(Pane.about)
                }
                ForEach(groups.indices, id: \.self) { i in
                    let panes = groups[i].filter(matches)
                    if !panes.isEmpty {
                        Section {
                            ForEach(panes) { pane in
                                Label {
                                    Text(pane.title)
                                } icon: {
                                    SettingsIcon(symbol: pane.symbol, color: pane.color)
                                }
                                .tag(pane)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Ara")
            .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 260)
        } detail: {
            detail(for: selection ?? .general)
                .id(selection)
                .navigationTitle((selection ?? .general).title)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button("Geri", systemImage: "chevron.left") { step(-1) }.disabled(position == 0)
                        Button("İleri", systemImage: "chevron.right") { step(1) }.disabled(position >= history.count - 1)
                    }
                }
        }
        .onChange(of: selection) { _, new in
            guard let new else { return }
            if navigatingHistory {
                navigatingHistory = false
                return
            }
            history = Array(history.prefix(position + 1)) + [new]
            position = history.count - 1
        }
        .background(WindowAccessor { $0.level = keepOnTop ? .floating : .normal })
        .onChange(of: keepOnTop) { _, on in NSApp.windows.forEach { $0.level = on ? .floating : .normal } }
    }

    @ViewBuilder
    private func detail(for pane: Pane) -> some View {
        switch pane {
        case .general: GeneralPane(open: { selection = $0 })
        case .corners: CornersPane()
        case .buttons: ButtonsPane()
        case .titlebar: TitlebarPane()
        case .apps: AppRulesPane()
        case .status: StatusPane()
        case .about: AboutPane()
        }
    }

    private func matches(_ pane: Pane) -> Bool {
        search.isEmpty || pane.title.localizedCaseInsensitiveContains(search)
            || pane.summary.localizedCaseInsensitiveContains(search)
    }

    private func step(_ delta: Int) {
        let target = position + delta
        guard history.indices.contains(target) else { return }
        position = target
        navigatingHistory = true
        selection = history[target]
    }
}

/// The account-style row at the top of the sidebar.
struct AccountRow: View {
    let enabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("MacTweak").font(.headline)
                Text(enabled ? "Etkin" : "Kapalı").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
