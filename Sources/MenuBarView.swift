import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    let quit: () -> Void

    static let width: CGFloat = 372

    static func preferredHeight(rowCount: Int) -> CGFloat {
        let rows = min(max(rowCount, 1), 6)
        return 166 + CGFloat(rows) * 47
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            summary
            backendList
            footer
        }
        .padding(12)
        .frame(width: Self.width, height: Self.preferredHeight(rowCount: model.backends.count), alignment: .top)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color(light: 0xFFF8EE, dark: 0x2A2520).opacity(0.62),
                        Color(light: 0xF7EFE2, dark: 0x211D19).opacity(0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .overlay(alignment: .bottom) {
            ToastOverlay(text: model.toast)
                .padding(.bottom, 4)
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
    }

    private var allOn: Bool {
        !model.backends.isEmpty && model.backends.allSatisfy(\.enabled)
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accent.opacity(0.16))
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accent)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("FreeAPI")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("本地 API 网关")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.ink3)
            }

            Spacer()

            Text("全部")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.ink3)
            Toggle("", isOn: Binding(get: { allOn }, set: { model.setAllEnabled($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Color.ok)
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 10)
    }

    private var summary: some View {
        HStack(spacing: 8) {
            Text("\(model.connectedCount) / \(model.backends.count) 已连接")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.ink3)
            Spacer()
            Picker("", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                Text("并行").tag(RunMode.parallel)
                Text("单路").tag(RunMode.single)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 100)
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 9)
    }

    @ViewBuilder
    private var backendList: some View {
        if model.backends.isEmpty {
            VStack(spacing: 6) {
                Text("还没有后端")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.ink2)
                Text("打开主窗口添加第一个地址")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ink3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        } else {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(model.backends) { backend in
                        row(backend)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ backend: Backend) -> some View {
        let state = model.state(for: backend)
        let selected = model.selectedID == backend.id

        return HStack(spacing: 8) {
            Button {
                model.select(backend.id)
            } label: {
                HStack(spacing: 8) {
                    StatusDot(state: state, size: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backend.name)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            TagPill(transport: backend.transport)
                            Text(backend.localAddress)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color.ink3)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(model.latencyText(for: backend))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(latencyColor(state))
                .frame(width: 44, alignment: .trailing)

            Button {
                Clipboard.copy(backend.endpoint)
                model.showToast("已复制 \(backend.name) 的地址")
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { model.backend(id: backend.id)?.enabled ?? backend.enabled },
                set: { model.setEnabled($0, for: backend.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Color.ok)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.selectionFill)
            }
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.glassStroke, lineWidth: 0.8)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
            HStack(spacing: 7) {
                Button {
                    model.openMainWindow(select: model.selectedID)
                    close()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "macwindow")
                        Text("打开主窗口")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(action: quit) {
                    Image(systemName: "power")
                }
                .buttonStyle(IconButtonStyle())
            }
        }
        .padding(.top, 10)
    }

    private func latencyColor(_ state: ConnectionState) -> Color {
        switch state {
        case .connected: return .ok
        case .connecting, .degraded: return .warn
        case .error: return .bad
        case .off: return .ink3
        }
    }
}
