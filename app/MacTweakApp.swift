import AppKit
import SwiftUI

@main
struct MacTweakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("MacTweak", id: "main") {
            RootView()
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: true))
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

/// The classic preferences layout: an icon grid ("Show All") that opens panes,
/// with back/forward, a grid button and search in the toolbar.
struct RootView: View {
    @State private var current: Pane?  // nil: the icon grid
    @State private var history: [Pane?] = [nil]
    @State private var position = 0
    @State private var search = ""
    @AppStorage(Key.keepOnTop) private var keepOnTop = false

    static let width: CGFloat = 680

    var body: some View {
        Group {
            if let pane = current {
                detail(for: pane)
                    .frame(width: Self.width, height: 600)
            } else {
                IconGrid(search: search, open: open)
                    .frame(width: Self.width)
            }
        }
        .navigationTitle(current?.title ?? "MacTweak")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Geri", systemImage: "chevron.left") { step(-1) }.disabled(position == 0)
                Button("İleri", systemImage: "chevron.right") { step(1) }.disabled(position >= history.count - 1)
                Button("Tümünü Göster", systemImage: "square.grid.3x3.fill") { open(nil) }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Ara")
        .onSubmit(of: .search) {
            // Enter opens the first matching pane, like System Preferences.
            if let first = Pane.allCases.first(where: { $0.matches(search) }) { open(first) }
        }
        .background(WindowAccessor { $0.level = keepOnTop ? .floating : .normal })
        .onChange(of: keepOnTop) { _, on in NSApp.windows.forEach { $0.level = on ? .floating : .normal } }
    }

    @ViewBuilder
    private func detail(for pane: Pane) -> some View {
        switch pane {
        case .general: GeneralPane(open: { open($0) })
        case .corners: CornersPane()
        case .buttons: ButtonsPane()
        case .titlebar: TitlebarPane()
        case .apps: AppRulesPane()
        case .status: StatusPane()
        case .about: AboutPane()
        }
    }

    private func open(_ pane: Pane?) {
        guard pane != current else { return }
        history = Array(history.prefix(position + 1)) + [pane]
        position = history.count - 1
        current = pane
        if pane != nil { search = "" }
    }

    private func step(_ delta: Int) {
        let target = position + delta
        guard history.indices.contains(target) else { return }
        position = target
        current = history[target]
    }
}

extension Pane {
    func matches(_ text: String) -> Bool {
        text.isEmpty || title.localizedCaseInsensitiveContains(text) || summary.localizedCaseInsensitiveContains(text)
    }
}

/// "Show All": the logo band at the top, then bands of large icons.
struct IconGrid: View {
    let search: String
    let open: (Pane) -> Void
    @AppStorage(Key.enabled) private var enabled = true

    private let bands: [[Pane]] = [[.general, .corners, .buttons, .titlebar], [.apps]]

    var body: some View {
        VStack(spacing: 0) {
            // Logo band, like the account row of System Preferences
            HStack(alignment: .center, spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 92, height: 92)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MacTweak").font(.system(size: 26, weight: .regular))
                    Text("Pencere ayarları · \(enabled ? "Etkin" : "Kapalı")")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GridIcon(pane: .status, dimmed: !Pane.status.matches(search), open: open)
                GridIcon(pane: .about, dimmed: !Pane.about.matches(search), open: open)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(Color(nsColor: .windowBackgroundColor))

            ForEach(bands.indices, id: \.self) { i in
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    ForEach(bands[i]) { pane in
                        GridIcon(pane: pane, dimmed: !pane.matches(search), open: open)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(i.isMultiple(of: 2) ? Color.primary.opacity(0.045) : Color.clear)
            }
        }
    }
}

/// One icon in the grid: large artwork with a two-line label underneath.
struct GridIcon: View {
    let pane: Pane
    var dimmed = false
    let open: (Pane) -> Void
    @State private var hovering = false

    var body: some View {
        Button { open(pane) } label: {
            VStack(spacing: 6) {
                PaneIcon(pane: pane, size: 52)
                    .scaleEffect(hovering ? 1.06 : 1)
                Text(pane.title)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .foregroundStyle(.primary)
            }
            .frame(width: 88)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.25 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.15), value: dimmed)
        .onHover { hovering = $0 }
        .help(pane.summary)
    }
}
