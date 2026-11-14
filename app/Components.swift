import AppKit
import SwiftUI

/// The rounded, colored icon tiles used by System Settings.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
    }
}

/// The card at the top of a pane: large icon, title and description, centered.
struct PaneHeader: View {
    let pane: Pane

    var body: some View {
        Section {
            VStack(spacing: 8) {
                SettingsIcon(symbol: pane.symbol, color: pane.color, size: 56)
                    .padding(.top, 6)
                Text(pane.title).font(.title2.bold())
                Text(pane.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A row that leads to another pane, like "General > About" in System Settings.
struct NavigationRow: View {
    let pane: Pane
    var value: String = ""
    let open: (Pane) -> Void

    var body: some View {
        Button { open(pane) } label: {
            HStack(spacing: 10) {
                SettingsIcon(symbol: pane.symbol, color: pane.color)
                Text(pane.title).foregroundStyle(.primary)
                Spacer()
                if !value.isEmpty { Text(value).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StatusRow: View {
    let title: String
    let ok: Bool
    let yes: String
    let no: String
    var relaxed = false  // the "ok" state relaxes a macOS defence
    var info: String?

    var body: some View {
        HStack {
            Text(title)
            if let info {
                Image(systemName: "info.circle").foregroundStyle(.secondary).help(info)
            }
            Spacer()
            Circle().fill(ok ? (relaxed ? Color.orange : Color.green) : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(ok ? yes : no).foregroundStyle(.secondary)
        }
    }
}

struct RadiusSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: 0...26, step: 0.5)
                Text(value.formatted(.number.precision(.fractionLength(0...1))) + " nk")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}

/// Access to the NSWindow behind a SwiftUI view.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { configure(w) } }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {}
}
