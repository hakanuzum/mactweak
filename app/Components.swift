import AppKit
import SwiftUI

/// A pane's icon: the bundled 3D artwork, or a neutral placeholder.
struct PaneIcon: View {
    let pane: Pane
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: pane.iconName, withExtension: "svg", subdirectory: "Icons"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "square.dashed").resizable()
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
    }
}

/// The card at the top of a pane: large icon, title and description, centered.
struct PaneHeader: View {
    let pane: Pane

    var body: some View {
        Section {
            VStack(spacing: 8) {
                PaneIcon(pane: pane, size: 64)
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
                PaneIcon(pane: pane, size: 24)
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
                Text(value.formatted(.number.precision(.fractionLength(0...1))) + " pt")
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
