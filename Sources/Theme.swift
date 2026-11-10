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

    static let ink = Color(light: 0x1F1E1D, dark: 0xF5F1E8)
    static let ink2 = Color(light: 0x5D584F, dark: 0xC2B9AA)
    static let ink3 = Color(light: 0x8D8578, dark: 0x8E8477)
    static let accent = Color(light: 0xB85C38, dark: 0xE29170)
    static let accentBright = Color(light: 0xD97757, dark: 0xF0A184)
    static let ok = Color(light: 0x4F8A63, dark: 0x7FC08F)
    static let okInk = Color(light: 0x37694A, dark: 0xA6D9B4)
    static let warn = Color(light: 0xB57B22, dark: 0xE6B25C)
    static let warnInk = Color(light: 0x8A5A12, dark: 0xF0CE93)
    static let bad = Color(light: 0xB8483A, dark: 0xE07868)
    static let badInk = Color(light: 0x943329, dark: 0xF0A79D)

    static let hairline = Color(light: 0x1F1E1D, dark: 0xFFF6E8, lightAlpha: 0.09, darkAlpha: 0.10)
    static let hairlineStrong = Color(light: 0x1F1E1D, dark: 0xFFF6E8, lightAlpha: 0.16, darkAlpha: 0.18)
    static let fieldFill = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.62, darkAlpha: 0.07)
    static let selectionFill = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.74, darkAlpha: 0.13)
    static let panelTint = Color(light: 0xFFFCF5, dark: 0x25221E, lightAlpha: 0.55, darkAlpha: 0.5)
    static let codeFill = Color(light: 0x483726, dark: 0x000000, lightAlpha: 0.06, darkAlpha: 0.26)
    static let glassStroke = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.45, darkAlpha: 0.12)
    static let buttonInk = Color(light: 0x2B1A12, dark: 0x2B1A12)
    static let sidebarTint = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.16, darkAlpha: 0.035)
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

struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                LinearGradient(
                    colors: scheme == .dark
                        ? [
                            Color(red: 0.11, green: 0.10, blue: 0.09),
                            Color(red: 0.10, green: 0.09, blue: 0.07),
                            Color(red: 0.07, green: 0.06, blue: 0.05)
                        ]
                        : [
                            Color(red: 0.988, green: 0.980, blue: 0.961),
                            Color(red: 0.969, green: 0.949, blue: 0.910),
                            Color(red: 0.949, green: 0.922, blue: 0.871)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color(light: 0xF1CFB0, dark: 0x6B3A25))
                    .frame(width: width * 0.78, height: width * 0.78)
                    .blur(radius: 92)
                    .offset(x: -width * 0.32, y: -height * 0.38)
                    .opacity(scheme == .dark ? 0.55 : 0.55)

                Circle()
                    .fill(Color(light: 0xE6C0AE, dark: 0x4A2B24))
                    .frame(width: width * 0.66, height: width * 0.66)
                    .blur(radius: 92)
                    .offset(x: width * 0.34, y: -height * 0.34)
                    .opacity(scheme == .dark ? 0.50 : 0.38)

                Circle()
                    .fill(Color(light: 0xD9D0B2, dark: 0x3F3A24))
                    .frame(width: width * 0.82, height: width * 0.82)
                    .blur(radius: 92)
                    .offset(x: width * 0.34, y: height * 0.46)
                    .opacity(scheme == .dark ? 0.42 : 0.40)

                Circle()
                    .fill(Color(light: 0xC3D2B8, dark: 0x2B3A2C))
                    .frame(width: width * 0.56, height: width * 0.56)
                    .blur(radius: 92)
                    .offset(x: -width * 0.36, y: height * 0.42)
                    .opacity(scheme == .dark ? 0.36 : 0.32)
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 14
    var padding: CGFloat = 12
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.panelTint.opacity(scheme == .dark ? 0.18 : 0.36))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.glassStroke, lineWidth: 1)
            }
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
            .font(.system(size: mono ? 10.5 : 11.5, design: mono ? .monospaced : .default))
            .focused($focused)
            .padding(.horizontal, 9)
            .frame(height: 31)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(focused ? Color.accent.opacity(0.55) : Color.hairline, lineWidth: focused ? 1.2 : 0.8)
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
            .frame(height: 31)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(focused ? Color.accent.opacity(0.55) : Color.hairline, lineWidth: focused ? 1.2 : 0.8)
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
                    .fill(state.statusColor.opacity(0.18))
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
        .background(Capsule().fill(state.statusColor.opacity(0.13)))
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
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.22), color.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
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
                .foregroundStyle(Color.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.78)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color.buttonInk)
            .padding(.horizontal, 12)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentBright, Color.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.ink2)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 0.8)
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
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 0.8)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
