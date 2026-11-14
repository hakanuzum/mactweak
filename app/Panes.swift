import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The panes in the sidebar. Titles and text are Turkish (user-facing).
enum Pane: String, CaseIterable, Identifiable {
    case general, corners, buttons, titlebar, apps, status, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Genel"
        case .corners: "Köşeler"
        case .buttons: "Düğmeler"
        case .titlebar: "Başlık Çubuğu"
        case .apps: "Uygulama Kuralları"
        case .status: "Durum"
        case .about: "Hakkında"
        }
    }

    /// KDE Oxygen artwork in Resources/Icons (LGPL-3.0, see assets/OXYGEN-ICONS-COPYING).
    var iconName: String { rawValue }

    var summary: String {
        switch self {
        case .general: "MacTweak'i açıp kapatın, oturum açılışında başlatın ve tüm ayar bölümlerine buradan ulaşın."
        case .corners: "Pencere köşelerinin ne kadar yuvarlak olacağını seçin. Değişiklik açık pencerelere hemen uygulanır."
        case .buttons: "Kapat, küçült ve büyüt düğmelerinin görünümünü seçin."
        case .titlebar: "Trafik ışıklarının yeri ve macOS 26 öncesi SDK ile derlenmiş uygulamaların başlık çubuğu ölçüleri."
        case .apps: "Bir uygulamayı MacTweak'ten hariç tutun ya da ona özel köşe yarıçapı verin."
        case .status: "Sistem güvenlik ayarları, arka plan ajanı ve açık uygulamalarda MacTweak'in durumu."
        case .about: "Sürüm, gizlilik ve bir sorun olursa yapılacaklar."
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
                            Text("MacTweak çalışmıyor").font(.headline)
                            Text("Başlatınca bundan sonra açılan uygulamalara uygulanır.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Başlat") { setAgent(true) }.buttonStyle(.borderedProminent)
                    }
                }
            }
            Section {
                Toggle("MacTweak'i etkinleştir", isOn: $enabled)
                Toggle("Oturum açılınca başlat", isOn: Binding(get: { agentInstalled }, set: { setAgent($0) }))
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }
            Section {
                NavigationRow(pane: .corners, value: CornerStyle.named(cornerStyle), open: open)
                NavigationRow(pane: .buttons, value: ButtonTheme.named(buttonTheme), open: open)
                NavigationRow(pane: .titlebar, open: open)
            }
            Section {
                NavigationRow(pane: .apps, value: rules.rules.isEmpty ? "" : "\(rules.rules.count) kural", open: open)
                NavigationRow(pane: .status, value: agentRunning ? "Çalışıyor" : "Çalışmıyor", open: open)
                NavigationRow(pane: .about, open: open)
            }
            Section("Diğer") {
                Toggle(isOn: $restartFinder) {
                    Text("Oturum açılışında Finder'ı yenile")
                    Text("Finder MacTweak'ten önce açılırsa bir kez yeniden başlatılır.")
                }
                Toggle("Bu pencere her zaman üstte", isOn: $keepOnTop)
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
            self.error = "Başlatılamadı: \(error.localizedDescription)"
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
            Section("Köşe stili") {
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
                Section("Özel yarıçap") {
                    RadiusSlider(title: "Üst köşeler", value: $customTop)
                    RadiusSlider(title: "Alt köşeler", value: $customBottom)
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
            Section {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(ButtonTheme.all) { t in
                        ThemeCard(theme: t, selected: theme == t.id).onTapGesture { theme = t.id }
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Tema")
            } footer: {
                Text("Simgeleri görmek için kartın üzerine gelin.")
            }
            Section {
                Toggle(isOn: $inactiveColor) {
                    Text("Arka plandaki pencerelerde de renkli kalsın")
                    Text("macOS arka plandaki pencerenin düğmelerini griye çevirir.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Title bar

struct TitlebarPane: View {
    @AppStorage(Key.indentTrafficLights) private var indent = false
    @AppStorage(Key.legacyTitlebarHeight) private var legacyHeight = false
    @AppStorage(Key.legacyButtonSpacing) private var legacySpacing = false

    var body: some View {
        Form {
            PaneHeader(pane: .titlebar)
            Section("Trafik ışıkları") {
                Toggle(isOn: $indent) {
                    Text("İçeri al ve ortala")
                    Text("Araç çubuğu olmayan pencerelerde düğmeleri kenardan uzaklaştırır ve başlık çubuğunda ortalar.")
                }
            }
            Section {
                Toggle(isOn: $legacyHeight) {
                    Text("Yeni başlık çubuğu yüksekliği")
                    Text("Başlık çubuğu 28 yerine 32 nokta olur.")
                }
                Toggle(isOn: $legacySpacing) {
                    Text("Yeni düğme aralığı")
                    Text("Düğmeler arası 20 yerine 23 nokta olur.")
                }
            } header: {
                Text("Eski uygulamalar")
            } footer: {
                Text("macOS 26 öncesi SDK ile derlenmiş uygulamalar (ör. Muxy, Zed, VLC) eski ölçüleri kullanır. Değişiklik uygulama yeniden açılınca görünür.")
            }
        }
        .formStyle(.grouped)
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
                Button("Uygulama Ekle…", systemImage: "plus", action: chooseApps)
            } header: {
                Text("Kurallar")
            } footer: {
                Text("Değişiklik açık pencerelere hemen uygulanır.")
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
                    Text("Otomatik hariç tutulanlar")
                } footer: {
                    Text("MacTweak yüklüyken çöken uygulamalar buraya alınır.")
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
        panel.prompt = "Ekle"
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
                    .help("Kuralı kaldır")
            }
            if rule.kind == .customRadius {
                RadiusSlider(title: "Üst", value: $rule.top).onChange(of: rule.top) { changed() }
                RadiusSlider(title: "Alt", value: $rule.bottom).onChange(of: rule.bottom) { changed() }
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
                StatusRow(title: "Sistem Bütünlük Koruması (SIP)", ok: info.sip, yes: "Kapalı", no: "Açık", relaxed: true,
                          info: "MacTweak'in diğer uygulamalara yüklenebilmesi için kapalı olmalı. Yalnızca Kurtarma Modu'nda değiştirilir.")
                StatusRow(title: "AMFI denetimi", ok: info.amfi, yes: "Kapalı", no: "Açık", relaxed: true,
                          info: "İmzalı uygulamalara kütüphane yüklenebilmesi için kapalı olmalı (boot-args).")
                StatusRow(title: "FileVault", ok: info.fileVault, yes: "Açık", no: "Kapalı",
                          info: "Disk şifrelemesi. MacTweak'le ilgisi yok; açık kalması önerilir.")
            } header: {
                Text("Sistem")
            } footer: {
                Text("SIP ve AMFI'nin kapalı olması macOS'un bir savunmasını gevşetir. MacTweak root yetkisi istemez ve sistem süreçlerine kod yüklemez; yalnızca sizin açtığınız uygulamalara yüklenir.")
            }
            Section("MacTweak") {
                StatusRow(title: "Arka plan ajanı", ok: info.agent, yes: "Çalışıyor", no: "Çalışmıyor")
                StatusRow(title: "Yeni uygulamalara yükleme", ok: info.environment, yes: "Açık", no: "Kapalı")
                if info.liquidRadius {
                    Label("Liquid Radius hâlâ etkin. İki araç aynı yerlere bağlanır; birini kapatın.",
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
                        case .active: Text("Etkin").foregroundStyle(.green)
                        case .inert: Text("Sistem penceresi").foregroundStyle(.secondary)
                        case .missing:
                            if relaunching.contains(app.processIdentifier) {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Yeniden Başlat") { relaunch(app) }.disabled(!info.environment)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Açık uygulamalar")
                    Spacer()
                    Button("Yenile", systemImage: "arrow.clockwise", action: load)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            } footer: {
                Text("MacTweak, ajan başladıktan sonra açılan uygulamalara yüklenir. Daha önce açılmış olanları yeniden başlatın.")
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
                    Text("Sürüm \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                        .foregroundStyle(.secondary)
                    Text("macOS 27 pencerelerini istediğiniz gibi ayarlayın: köşeler, düğmeler, başlık çubuğu.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            Section {
                LabeledContent("Veri gönderimi", value: "Yok, ağ bağlantısı kurmaz")
                LabeledContent("Root yetkisi", value: "Gerekmez")
                LabeledContent("Çökme koruması", value: "Çöken uygulamayı hariç tutar")
            }
            Section {
                Text("Bir uygulama açılmıyorsa Uygulama Kuralları'ndan hariç tutun. Hiçbir şey açılmıyorsa Mac'i Güvenli Mod'da başlatın (oturum ajanları çalışmaz) ve MacTweak'i kaldırın.")
                    .foregroundStyle(.secondary)
                Button("MacTweak'i Kaldır…", role: .destructive) { confirmRemove = true }
            } header: {
                Text("Sorun olursa")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("MacTweak kaldırılsın mı?", isPresented: $confirmRemove) {
            Button("Kaldır", role: .destructive) {
                SystemControl.removeEverything()
                NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in NSApp.terminate(nil) }
            }
        } message: {
            Text("Ajan durur, açık pencereler varsayılana döner ve uygulama Çöp Sepeti'ne taşınır. Tercihler silinmez.")
        }
    }
}
