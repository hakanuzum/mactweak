import AppKit
import Foundation

/// System status, agent installation and running apps.
enum SystemControl {
    static let agentLabel = "dev.hakanuzum.mactweak.agent"
    static var agentPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }
    static var corePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacTweak/libmactweak.dylib").path
    }
    static var agentExecutable: String { Bundle.main.bundlePath + "/Contents/MacOS/mactweak-agent" }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Security settings

    static var sipDisabled: Bool { run("/usr/bin/csrutil", ["status"]).contains("disabled") }
    static var amfiDisabled: Bool { run("/usr/sbin/nvram", ["boot-args"]).contains("amfi_get_out_of_my_way=1") }
    static var fileVaultOn: Bool { run("/usr/bin/fdesetup", ["isactive"]) == "true" }

    // MARK: Agent

    static var agentInstalled: Bool { FileManager.default.fileExists(atPath: agentPlist.path) }

    static func installAgent() throws {
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MacTweak")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [agentExecutable],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Background",
            "LimitLoadToSessionType": "Aqua",
            "StandardErrorPath": logs.appendingPathComponent("agent.log").path,
            "EnvironmentVariables": ["MACTWEAK_DISABLE": "1"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: agentPlist, options: .atomic)
        let domain = "gui/\(getuid())"
        run("/bin/launchctl", ["bootout", "\(domain)/\(agentLabel)"])
        run("/bin/launchctl", ["bootstrap", domain, agentPlist.path])
    }

    /// Stops the agent and removes the core from the environment. Open windows return to
    /// the default; newly opened apps do not load the core.
    static func uninstallAgent() {
        run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(agentLabel)"])
        try? FileManager.default.removeItem(at: agentPlist)
        removeFromEnvironment()
    }

    static func removeFromEnvironment() {
        let current = run("/bin/launchctl", ["getenv", "DYLD_INSERT_LIBRARIES"])
        let rest = current.split(separator: ":").map(String.init).filter { !$0.isEmpty && $0 != corePath }
        if rest.isEmpty {
            run("/bin/launchctl", ["unsetenv", "DYLD_INSERT_LIBRARIES"])
        } else {
            run("/bin/launchctl", ["setenv", "DYLD_INSERT_LIBRARIES", rest.joined(separator: ":")])
        }
    }

    static var inEnvironment: Bool {
        run("/bin/launchctl", ["getenv", "DYLD_INSERT_LIBRARIES"]).split(separator: ":").contains { $0 == corePath }
    }

    // MARK: Liquid Radius

    static var liquidRadiusActive: Bool {
        run("/bin/launchctl", ["getenv", "DYLD_INSERT_LIBRARIES"]).contains("LiquidRadius")
            || !run("/bin/launchctl", ["print", "gui/\(getuid())/com.liquidradius.injection"]).contains("Could not find")
    }

    // MARK: Running apps

    enum LoadState { case active, outdated, inert, missing }

    /// Build stamp of the core this app ships (build.sh writes it into Info.plist).
    static let coreBuild = (Bundle.main.object(forInfoDictionaryKey: "MTCoreBuild") as? Int).map(UInt64.init) ?? 0

    static func loadState(_ pid: pid_t) -> LoadState {
        let s = Notify.state(Notify.alivePrefix + String(pid))
        switch s & 0xFF {
        case 1: return (s >> 8) == coreBuild ? .active : .outdated
        case 2: return .inert
        default: return .missing
        }
    }

    static var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    /// Quits and reopens an app; launched through LaunchServices, it picks up the core.
    static func relaunch(_ app: NSRunningApplication) async {
        guard let url = app.bundleURL else { return }
        if app.bundleIdentifier == "com.apple.finder" {
            run("/usr/bin/killall", ["Finder"])
            return
        }
        app.terminate()
        for _ in 0..<50 where !app.isTerminated { try? await Task.sleep(for: .milliseconds(100)) }
        guard app.isTerminated else { return }  // e.g. an unsaved document kept it open
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Removes MacTweak completely (except the app bundle and preferences).
    static func removeEverything() {
        uninstallAgent()
        let fm = FileManager.default
        try? fm.removeItem(atPath: (corePath as NSString).deletingLastPathComponent)
        try? fm.removeItem(at: fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MacTweak"))
    }
}
