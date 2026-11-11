import SwiftUI
import AppKit

private func nsColor(hex: UInt32, alpha: CGFloat) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

extension Color {
    init(
        light: UInt32,
        dark: UInt32,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1
    ) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return nsColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    // LiquidBar flat palette
    static let canvas = Color(light: 0xF7F5EF, dark: 0x1A1917)
    static let surface = Color(light: 0xFDFCF8, dark: 0x24221F)
    static let surfaceMuted = Color(light: 0xF0EDE3, dark: 0x2C2A26)
    static let surfaceStrong = Color(light: 0xE9E5D9, dark: 0x35322D)
    static let border = Color(light: 0xE3DFD2, dark: 0x3A3731)

    static let ink = Color(light: 0x23211D, dark: 0xF1EEE5)
    static let ink2 = Color(light: 0x6F6A60, dark: 0xACA79C)
    static let ink3 = Color(light: 0x99948A, dark: 0x807B71)

    static let accent = Color(light: 0xC2603F, dark: 0xE08A6B)
    static let accentBright = Color(light: 0xD97757, dark: 0xD97757)
    static let accentSoft = Color(light: 0xF6E4DB, dark: 0x3B2C26)
    static let onAccent = Color(light: 0xFFF9F5, dark: 0xFFF9F5)

    static let ok = Color(light: 0x2F6F5E, dark: 0x7CC3A7)
    static let okInk = Color(light: 0x2F6F5E, dark: 0x7CC3A7)
    static let warn = Color(light: 0xA9611F, dark: 0xE5AE6B)
    static let warnInk = Color(light: 0xA9611F, dark: 0xE5AE6B)
    static let bad = Color(light: 0xA83224, dark: 0xF0806A)
    static let badInk = Color(light: 0xA83224, dark: 0xF0806A)

    // Legacy names kept for existing views.
    static let hairline = Color(light: 0xE3DFD2, dark: 0x3A3731)
    static let hairlineStrong = Color(light: 0xD8D2C3, dark: 0x4A463E)
    static let fieldFill = Color(light: 0xFDFCF8, dark: 0x24221F)
    static let selectionFill = Color(light: 0xF6E4DB, dark: 0x3B2C26)
    static let panelTint = Color(light: 0xFDFCF8, dark: 0x24221F)
    static let codeFill = Color(light: 0xF0EDE3, dark: 0x2C2A26)
    static let glassStroke = Color(light: 0xE3DFD2, dark: 0x3A3731)
    static let buttonInk = Color(light: 0xFFF9F5, dark: 0xFFF9F5)
    static let sidebarTint = Color(light: 0xF7F5EF, dark: 0x1A1917)
}

extension ConnectionState {
    var statusColor: Color {
        switch self {
        case .connected: return .ok
        case .connecting, .degraded: return .warn
        case .error: return .bad
        case .off: return .ink3
        }
    }

    var statusInk: Color {
        switch self {
        case .connected: return .okInk
        case .connecting, .degraded: return .warnInk
        case .error: return .badInk
        case .off: return .ink3
        }
    }
}

enum Typography {
    static func wordmark(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func display(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func numeral(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

struct AuroraBackground: View {
    var body: some View {
        Color.canvas.ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.border, lineWidth: 1)
            )
    }
}

struct GlassTextField: View {
    @Binding var text: String
    var mono: Bool = false
    var placeholder: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: mono ? 10.5 : 12, design: mono ? .monospaced : .default))
            .focused($focused)
            .padding(.horizontal, 9)
            .frame(height: 33)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(focused ? Color.accent.opacity(0.55) : Color.border, lineWidth: focused ? 1.2 : 1)
            )
    }
}

struct GlassNumberField: View {
    @Binding var value: Int
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", value: $value, format: .number.grouping(.never))
            .textFieldStyle(.plain)
            .font(.system(size: 10.5, design: .monospaced))
            .focused($focused)
            .padding(.horizontal, 9)
            .frame(height: 33)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(focused ? Color.accent.opacity(0.55) : Color.border, lineWidth: focused ? 1.2 : 1)
            )
    }
}

struct LabeledField<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.ink3)
                if let hint {
                    Text(hint)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.ink3)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.ink3.opacity(0.12))
                        )
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusDot: View {
    let state: ConnectionState
    var size: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        ZStack {
            if state != .off {
                Circle()
                    .fill(state.statusColor.opacity(0.14))
                    .frame(width: size + 6, height: size + 6)
                    .scaleEffect(state == .connecting && pulse ? 1.15 : 1)
            }
            Circle()
                .fill(state.statusColor)
                .frame(width: size, height: size)
        }
        .onAppear {
            guard state == .connecting else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct StatusChip: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.statusColor)
                .frame(width: 6, height: 6)
            Text(state.label)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(state.statusInk)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(state.statusColor.opacity(0.12)))
        .overlay(Capsule().strokeBorder(state.statusColor.opacity(0.18), lineWidth: 0.5))
    }
}

struct TagPill: View {
    let transport: BackendTransport

    var body: some View {
        Text(transport.shortLabel)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(transport == .ssh ? Color.accent : Color.ink2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4.5)
                    .fill((transport == .ssh ? Color.accent : Color.ink2).opacity(0.10))
            )
    }
}

struct Sparkline: View {
    let values: [Int]
    var color: Color = .ok

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let data = values.isEmpty ? [1, 1, 1, 1] : values
            let minimum = data.min() ?? 0
            let maximum = data.max() ?? 1
            let span = max(1, maximum - minimum)
            let points: [CGPoint] = data.enumerated().map { index, value in
                let x = data.count <= 1
                    ? size.width
                    : size.width * CGFloat(index) / CGFloat(data.count - 1)
                let normalized = CGFloat(value - minimum) / CGFloat(span)
                let y = 2 + (size.height - 4) * (1 - normalized)
                return CGPoint(x: x, y: y)
            }

            ZStack {
                areaPath(points, size: size)
                    .fill(color.opacity(0.10))
                linePath(points)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let middleX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: middleX, y: previous.y),
                control2: CGPoint(x: middleX, y: current.y)
            )
        }
        return path
    }

    private func areaPath(_ points: [CGPoint], size: CGSize) -> Path {
        var path = linePath(points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

struct ToastOverlay: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.onAccent)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color(light: 0x23211D, dark: 0x3A3731)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.onAccent)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentBright)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.ink2)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SidebarActionButtonStyle: ButtonStyle {
    var prominent: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color.onAccent : Color.ink2)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? Color.accentBright : Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Color.border, lineWidth: 1)
            )
            .opacity(!isEnabled ? 0.35 : (configuration.isPressed ? 0.8 : 1))
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
