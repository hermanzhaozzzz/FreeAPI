import SwiftUI
import AppKit

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = ProcessInfo.processInfo.environment["FREEAPI_SHOW_SETTINGS"] == "1"

    var body: some View {
        ZStack {
            AuroraBackground()
            HStack(spacing: 0) {
                SidebarView(model: model, openSettings: { showSettings = true })
                    .frame(width: 300)
                Rectangle()
                    .fill(Color.hairline)
                    .frame(width: 1)
                DetailView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(.ultraThinMaterial)
        }
        .overlay(alignment: .bottom) {
            ToastOverlay(text: model.toast)
                .padding(.bottom, 16)
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .frame(minWidth: 920, minHeight: 640)
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct SidebarView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            modeCard
            searchField
            listHeader
            backendList
            Spacer(minLength: 8)
            footer
        }
        .padding(.top, 52)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background(Color.sidebarTint)
    }

    private var brand: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accent.opacity(0.16))
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accent)
            }
            .frame(width: 26, height: 26)

            Text("FreeAPI")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ink)
            Text("2.0")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.ink3)
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("运行模式")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ink3)
                Spacer()
                Text("\(model.enabledCount) 个运行中")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.ink3)
            }
            Picker("", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                Text("并行").tag(RunMode.parallel)
                Text("单路").tag(RunMode.single)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            Text(model.mode.note)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.panelTint.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 0.8)
        )
        .padding(.horizontal, 6)
        .padding(.top, 16)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.ink3)
            TextField("搜索后端", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 0.8)
        )
        .padding(.horizontal, 6)
        .padding(.top, 14)
    }

    private var listHeader: some View {
        HStack(spacing: 6) {
            Text("后端")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.ink3)
            Text("\(model.filteredBackends.count)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.ink3)
                .padding(.horizontal, 5)
                .frame(height: 15)
                .background(Capsule().fill(Color.ink3.opacity(0.12)))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 16)
        .padding(.bottom, 7)
    }

    private var backendList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(model.filteredBackends) { backend in
                    BackendRowView(model: model, backend: backend)
                }
                if model.filteredBackends.isEmpty && !model.searchText.isEmpty {
                    Text("没有匹配的后端")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.ink3)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
            HStack(spacing: 6) {
                Button {
                    openSettings()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("添加后端")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
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
                }
                .buttonStyle(.plain)
                .help("高级设置与后端管理")
            }
        }
        .padding(.top, 8)
    }
}

private struct BackendRowView: View {
    @ObservedObject var model: AppModel
    let backend: Backend

    var body: some View {
        let state = model.state(for: backend)
        let selected = model.selectedID == backend.id

        HStack(spacing: 9) {
            StatusDot(state: state)
            VStack(alignment: .leading, spacing: 2) {
                Text(backend.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    TagPill(transport: backend.transport)
                    Text(backend.localAddress)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.ink3)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(model.latencyText(for: backend))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(latencyColor(state))
                }
            }
            Toggle("", isOn: Binding(
                get: { model.backend(id: backend.id)?.enabled ?? backend.enabled },
                set: { model.setEnabled($0, for: backend.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Color.ok)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.selectionFill)
            }
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.glassStroke, lineWidth: 0.8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.select(backend.id)
        }
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

private struct DetailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let backend = model.selectedID.flatMap({ model.backend(id: $0) }) ?? model.backends.first {
            DetailContent(model: model, backend: backend)
                .id(backend.id)
        } else {
            EmptyDetailView(model: model)
        }
    }
}

private struct DetailContent: View {
    @ObservedObject var model: AppModel
    let backend: Backend

    @State private var revealKey = false

    private var state: ConnectionState { model.state(for: backend) }
    private var runtime: BackendRuntime { model.runtime(for: backend.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            signal
            if let message = runtime.errorMessage, !message.isEmpty {
                errorLine(message)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    connectionSection
                    sectionDivider
                    credentialsSection
                    if backend.transport == .ssh {
                        sectionDivider
                        sshSection
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                TextField("", text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: 470, alignment: .leading)

                HStack(spacing: 8) {
                    StatusChip(state: state)
                    Text(backend.upstreamAddress)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.ink2)
                    Text(backend.transport.label)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.ink3)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.ink3.opacity(0.10))
                        )
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Text("启用")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ink3)
                Toggle("", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .tint(Color.ok)
            }
            .padding(.top, 5)
        }
        .padding(.top, 32)
        .padding(.horizontal, 34)
        .padding(.bottom, 15)
    }

    private var signal: some View {
        HStack(spacing: 13) {
            HStack(spacing: 7) {
                StatusDot(state: state)
                Text(state.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ink)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(runtime.latency.map { String($0) } ?? "—")
                    .font(.system(size: 19, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText())
                Text("ms")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.ink3)
            }

            Sparkline(values: runtime.history, color: state == .off ? .ink3 : state.statusColor)
                .frame(width: 158, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("HTTP \(runtime.httpStatus.map { String($0) } ?? "—")")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.ink3)
                Text("检查于 \(model.lastCheckedText(for: backend))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.ink3)
            }

            Spacer(minLength: 8)

            Button {
                model.testConnection(backend.id)
            } label: {
                HStack(spacing: 6) {
                    if model.isTesting(backend.id) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(model.isTesting(backend.id) ? "正在测试" : "测试连接")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isTesting(backend.id))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(state == .off ? Color.clear : state.statusColor.opacity(0.06))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    state == .off ? Color.hairline : state.statusColor.opacity(0.18),
                    lineWidth: 0.8
                )
        }
        .padding(.horizontal, 32)
    }

    private func errorLine(_ message: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9.5))
            Text(message)
                .font(.system(size: 10))
                .lineLimit(2)
        }
        .foregroundStyle(state == .error ? Color.bad : Color.warn)
        .padding(.horizontal, 34)
        .padding(.top, 5)
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("连接方式")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text(backend.transport == .ssh
                         ? "经跳板机转发；本机监听 127.0.0.1，服务器地址必须能被跳板机访问。"
                         : "客户端直接连接服务器地址，本机不启动转发进程。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Text("SSH 隧道")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.ink2)
                    Toggle("", isOn: transportBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Color.ok)
                }
            }

            GlassCard(cornerRadius: 13, padding: 12) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 10
                ) {
                    LabeledField(label: "服务器地址") {
                        GlassTextField(text: hostBinding, mono: true)
                    }
                    LabeledField(label: "端口") {
                        GlassNumberField(value: portBinding)
                    }
                    if backend.transport == .direct {
                        LabeledField(label: "协议") {
                            schemePicker
                        }
                    }
                    LabeledField(label: "API 路径") {
                        GlassTextField(text: pathBinding, mono: true)
                    }
                    if backend.transport == .ssh {
                        LabeledField(label: "本地端口", hint: "自动") {
                            GlassNumberField(value: localPortBinding)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 15)
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("凭据")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("保存在 macOS 钥匙串；用于连通性测试，不写入配置文件或日志。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ink3)
            }

            GlassCard(cornerRadius: 13, padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledField(label: "API Key") {
                        secretField
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "lock")
                            .font(.system(size: 10))
                        Text("不随配置导出，也不会出现在连接日志里。")
                            .font(.system(size: 9.5))
                    }
                    .foregroundStyle(Color.ink3)
                }
            }
        }
        .padding(.vertical, 15)
    }

    private var sshSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("跳板机")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("服务器地址必须能被跳板机访问。密钥和 ProxyJump 可以写在 ~/.ssh/config 里。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ink3)
            }

            GlassCard(cornerRadius: 13, padding: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledField(label: "SSH 目标") {
                        GlassTextField(
                            text: sshBinding,
                            mono: true,
                            placeholder: "user@bastion.example.com 或 Host 别名"
                        )
                    }
                    commandBlock
                }
            }
        }
        .padding(.vertical, 15)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var commandBlock: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                Text("生成的 SSH 命令")
                    .font(.system(size: 9.5, weight: .semibold))
                Spacer()
                Button {
                    Clipboard.copy(backend.sshCommand)
                    model.showToast("已复制 SSH 命令")
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("复制")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accent)
            }
            .foregroundStyle(Color.ink3)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)

            Text(backend.sshCommand)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.ink2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)

            Text("固定启用 BatchMode 与严格主机校验；端口、密钥、跳板链沿用你的 SSH 配置。")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.codeFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 0.8)
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("客户端使用")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.ink3)
            Text(backend.endpoint)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.codeFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 0.8)
                )
            Spacer(minLength: 8)
            Button {
                Clipboard.copy(backend.endpoint)
                model.showToast("已复制 API 地址")
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.doc")
                    Text("复制地址")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 11)
        .background(Color.panelTint.opacity(0.10))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
    }

    private var schemePicker: some View {
        Picker("", selection: schemeBinding) {
            Text("https").tag("https")
            Text("http").tag("http")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(height: 31)
    }

    private var secretField: some View {
        HStack(spacing: 6) {
            Group {
                if revealKey {
                    TextField("sk-…", text: keyBinding)
                } else {
                    SecureField("sk-…", text: keyBinding)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 10.5, design: .monospaced))

            Button {
                revealKey.toggle()
            } label: {
                Image(systemName: revealKey ? "eye.slash" : "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .frame(height: 31)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { model.backend(id: backend.id)?.name ?? backend.name },
            set: { value in model.updateBackend(id: backend.id) { $0.name = value } }
        )
    }

    private var hostBinding: Binding<String> {
        Binding(
            get: { model.backend(id: backend.id)?.host ?? backend.host },
            set: { value in model.updateBackend(id: backend.id) { $0.host = value } }
        )
    }

    private var portBinding: Binding<Int> {
        Binding(
            get: { model.backend(id: backend.id)?.port ?? backend.port },
            set: { value in model.updateBackend(id: backend.id) { $0.port = value } }
        )
    }

    private var pathBinding: Binding<String> {
        Binding(
            get: { model.backend(id: backend.id)?.apiPath ?? backend.apiPath },
            set: { value in model.updateBackend(id: backend.id) { $0.apiPath = value } }
        )
    }

    private var schemeBinding: Binding<String> {
        Binding(
            get: { model.backend(id: backend.id)?.scheme ?? backend.scheme },
            set: { value in model.updateBackend(id: backend.id) { $0.scheme = value } }
        )
    }

    private var localPortBinding: Binding<Int> {
        Binding(
            get: { model.backend(id: backend.id)?.localPort ?? 0 },
            set: { value in
                model.updateBackend(id: backend.id) {
                    $0.localPort = value > 0 ? value : nil
                }
            }
        )
    }

    private var sshBinding: Binding<String> {
        Binding(
            get: { model.backend(id: backend.id)?.sshTarget ?? backend.sshTarget },
            set: { value in model.updateBackend(id: backend.id) { $0.sshTarget = value } }
        )
    }

    private var keyBinding: Binding<String> {
        Binding(
            get: { model.apiKey(for: backend.id) },
            set: { value in model.setAPIKey(value, for: backend.id) }
        )
    }

    private var transportBinding: Binding<Bool> {
        Binding(
            get: { (model.backend(id: backend.id)?.transport ?? backend.transport) == .ssh },
            set: { value in
                model.setTransport(value ? .ssh : .direct, for: backend.id)
            }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.backend(id: backend.id)?.enabled ?? backend.enabled },
            set: { value in model.setEnabled(value, for: backend.id) }
        )
    }
}

private struct EmptyDetailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.accent)
            }
            Text("还没有后端")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.ink)
            Text("添加一个服务器地址，决定是否经 SSH 跳板机转发。")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.ink3)
            if let error = model.startupError {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.bad)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            HStack(spacing: 8) {
                Button {
                    model.addBackend(transport: .ssh)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("SSH 后端")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    model.addBackend(transport: .direct)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                        Text("直连后端")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
