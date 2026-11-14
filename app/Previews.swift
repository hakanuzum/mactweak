import SwiftUI

/// Corner style card: a small window on a desktop, all four corners visible.
struct StyleCard: View {
    let style: CornerStyle
    let top: Double
    let bottom: Double
    let selected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Wallpaper()
                MiniWindow(top: top, bottom: bottom).frame(width: 112, height: 70)
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 3 : 1)
            }
            Text(style.name)
                .font(.callout.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }
}

struct Wallpaper: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.16, green: 0.42, blue: 0.55), Color(red: 0.36, green: 0.31, blue: 0.62),
                     Color(red: 0.86, green: 0.55, blue: 0.47)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct MiniWindow: View {
    let top: Double
    let bottom: Double

    var body: some View {
        // The card is small, so the radius is scaled; proportions match a real window.
        let k = 0.62
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: top * k, bottomLeadingRadius: bottom * k,
            bottomTrailingRadius: bottom * k, topTrailingRadius: top * k, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in TrafficLight(theme: 1, index: i, size: 7) }
            }
            .padding(.leading, 7)
            .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
            .background(Color(white: 0.93))
            Rectangle().fill(Color.white)
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.black.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

/// One traffic light; the SwiftUI twin of the drawing in core/buttons.m.
struct TrafficLight: View {
    let theme: Int
    let index: Int  // 0 close, 1 minimize, 2 zoom
    let size: CGFloat
    var hovering = false

    var body: some View {
        let fill = ButtonTheme.color(theme: theme, index: index)
        let d = theme == 5 ? size * 0.64 : size
        ZStack {
            switch theme {
            case 2:
                RoundedRectangle(cornerRadius: d * 0.28, style: .continuous).fill(fill)
            case 3 where !hovering:
                Circle().strokeBorder(fill, lineWidth: max(1.2, d * 0.12))
            default:
                Circle().fill(fill)
            }
            if theme != 2 && !(theme == 3 && !hovering) {
                Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
            }
            if hovering && theme != 5 {
                Glyph(index: index)
                    .stroke(theme == 4 ? Color.white.opacity(0.9) : Color.black.opacity(0.55),
                            style: StrokeStyle(lineWidth: max(1.1, d * 0.11), lineCap: .round))
            }
        }
        .frame(width: d, height: d)
        .frame(width: size, height: size)
    }
}

struct Glyph: Shape {
    let index: Int

    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), d = r.width * 0.24
        if index == 0 {
            p.move(to: CGPoint(x: c.x - d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
            p.move(to: CGPoint(x: c.x - d, y: c.y + d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y - d))
        } else {
            p.move(to: CGPoint(x: c.x - d * 1.2, y: c.y)); p.addLine(to: CGPoint(x: c.x + d * 1.2, y: c.y))
            if index == 2 {
                p.move(to: CGPoint(x: c.x, y: c.y - d * 1.2)); p.addLine(to: CGPoint(x: c.x, y: c.y + d * 1.2))
            }
        }
        return p
    }
}

/// Button theme card: a title bar strip; hovering shows the glyphs.
struct ThemeCard: View {
    let theme: ButtonTheme
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                ForEach(0..<3) { i in
                    TrafficLight(theme: theme.id == 0 ? 1 : theme.id, index: i, size: 14, hovering: hovering)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 3 : 1)
            }
            Text(theme.name)
                .font(.callout.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
