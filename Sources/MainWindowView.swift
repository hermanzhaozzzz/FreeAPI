import SwiftUI
import AppKit

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @State private var showAdd = ProcessInfo.processInfo.environment["FREEAPI_SHOW_ADD"] == "1"
    @State private var showSettings = ProcessInfo.processInfo.environment["FREEAPI_SHOW_SETTINGS"] == "1"
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                model: model,
                add: { showAdd = true },
                settings: { showSettings = true },
                requestDelete: {
                    if !model.selectedIDs.isEmpty { confirmDelete = true }
                }
            )
            .frame(width: 280)

            Rectangle()
                .fill(Color.border)
                .frame(width: 1)

            DetailView(model: model, add: { showAdd = true })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.canvas)
        .overlay(alignment: .bottom) {
            ToastOverlay(text: model.toast)
                .padding(.bottom, 16)
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .frame(minWidth: 920, minHeight: 640)
        .sheet(isPresented: $showAdd) {
            AddServiceView(model: model)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
        .alert(deleteTitle, isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                model.deleteSelected()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteTitle: String {
        model.selectedBackends.count == 1 ? "删除服务？" : "删除 \(model.selectedBackends.count) 个服务？"
    }

    private var deleteMessage: String {
        let selected = model.selectedBackends
        guard !selected.isEmpty else { return "" }
        let names = selected.map { "「\($0.name)」" }.joined(separator: "、")
        return "将移除\(names)及其 API Key，此操作不可撤销。"
    }
}

private struct SidebarView: View {
    @ObservedObject var model: AppModel
    let add: () -> Void
    let settings: () -> Void
    let requestDelete: () -> Void
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            searchField
            listHeader
            serviceList
            Spacer(minLength: 0)
            actionBar
        }
        .padding(.top, 52)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background(Color.canvas)
    }

    private var filtered: [Backend] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.backends }
        return model.backends.filter { ($0.name + " " + $0.host).lowercased().contains(query) }
    }

    private var toggleHelp: String {
        let selected = model.selectedBackends
        return !selected.isEmpty && selected.allSatisfy(\.enabled) ? "禁用选中服务" : "启用选中服务"
    }

    private var brand: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentSoft)
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accent)
            }
            .frame(width: 26, height: 26)

            Text("FreeAPI")
                .font(Typography.wordmark(16))
                .foregroundStyle(Color.ink)
            Text("3.0")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.ink3)
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.ink3)
            TextField("搜索服务", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.border, lineWidth: 1)
        )
        .padding(.horizontal, 6)
        .padding(.top, 16)
    }

    private var listHeader: some View {
        HStack(spacing: 6) {
            Text("服务")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.ink3)
            Text("\(filtered.count)")
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

    private var serviceList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if filtered.isEmpty {
                    VStack(spacing: 5) {
                        Text(model.backends.isEmpty ? "还没有服务" : "没有匹配的服务")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.ink2)
                        if model.backends.isEmpty {
                            Text("用下面的 + 添加第一个")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.ink3)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(filtered) { backend in
                        ServiceRow(
                            model: model,
                            backend: backend,
                            selected: model.selectedIDs.contains(backend.id),
                            primary: model.selectedID == backend.id,
                            action: {
                                model.select(
                                    backend.id,
                                    extending: NSEvent.modifierFlags.contains(.shift),
                                    within: filtered.map(\.id)
                                )
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
            HStack(spacing: 6) {
                Button(action: add) {
                    Image(systemName: "plus")
                }
                .buttonStyle(SidebarActionButtonStyle(prominent: true))
                .help("添加服务")

                Button(action: requestDelete) {
                    Image(systemName: "minus")
                }
                .buttonStyle(SidebarActionButtonStyle())
                .disabled(model.selectedIDs.isEmpty)
                .help("删除选中服务")

                Button {
                    model.toggleSelectedEnabled()
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(SidebarActionButtonStyle())
                .disabled(model.selectedIDs.isEmpty)
                .help(toggleHelp)

                Spacer()

                Button(action: settings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(SidebarActionButtonStyle())
                .help("设置")
            }
        }
        .padding(.top, 8)
    }
}

private struct ServiceRow: View {
    @ObservedObject var model: AppModel
    let backend: Backend
    let selected: Bool
    let primary: Bool
    let action: () -> Void

    var body: some View {
        let state = model.state(for: backend)
        let address = backend.transport == .ssh
            ? "127.0.0.1:\(backend.localPort ?? 0)"
            : backend.host
        let latency = backend.enabled ? model.latencyText(for: backend) : "已禁用"

        Button(action: action) {
            HStack(spacing: 9) {
                StatusDot(state: state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(backend.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Color.accent : Color.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        TagPill(transport: backend.transport)
                        Text(address)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color.ink3)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(latency)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(latencyColor(state))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentSoft)
                }
            }
            .overlay {
                if primary {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.accent.opacity(0.42), lineWidth: 1)
                }
            }
            .overlay(alignment: .leading) {
                if primary {
                    Capsule()
                        .fill(Color.accent)
                        .frame(width: 3, height: 22)
                        .padding(.leading, 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func latencyColor(_ state: ConnectionState) -> Color {
        guard backend.enabled else { return .ink3 }
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
    let add: () -> Void

    var body: some View {
        if let id = model.selectedID, let backend = model.backend(id: id) {
            DetailContent(model: model, backend: backend)
                .id(backend.id)
        } else {
            EmptyDetailView(model: model, add: add)
        }
    }
}

private struct DetailContent: View {
    @ObservedObject var model: AppModel
    let backend: Backend

    @State private var editingConnection = false
    @State private var showAdvanced = false
    @State private var revealKey = false
    @State private var addressText = ""
    @State private var jumpTarget = ""
    @State private var useJump = false
    @State private var localPort = 18189
    @State private var editError: String?

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
                VStack(alignment: .leading, spacing: 12) {
                    connectionCard
                    credentialsCard
                }
                .padding(.horizontal, 34)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            footer
        }
        .onAppear(perform: syncDrafts)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("", text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(Typography.display(24))
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: 470, alignment: .leading)

                HStack(spacing: 8) {
                    StatusChip(state: state)
                    Text(verbatim: "\(backend.host):\(backend.port)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.ink2)
                    TagPill(transport: backend.transport)
                }
            }
            Spacer(minLength: 12)
        }
        .padding(.top, 32)
        .padding(.horizontal, 34)
        .padding(.bottom, 14)
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
                    .font(Typography.numeral(20))
                    .foregroundStyle(Color.ink)
                Text("ms")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.ink3)
            }

            Sparkline(values: runtime.history, color: state == .off ? .ink3 : state.statusColor)
                .frame(width: 150, height: 30)

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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(state == .off ? Color.surfaceMuted : Color.ok.opacity(0.07))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    state == .off ? Color.border : Color.ok.opacity(0.18),
                    lineWidth: 1
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

    private var connectionCard: some View {
        GlassCard(cornerRadius: 12, padding: 14) {
            if editingConnection {
                connectionEditor
            } else {
                connectionSummary
            }
        }
    }

    private var connectionSummary: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentSoft)
                Image(systemName: backend.transport == .ssh ? "link" : "globe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(backend.transport == .ssh ? "经跳板机" : "直连")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text(connectionSummaryText)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("编辑") {
                beginEditing()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var connectionEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField(label: "API 地址") {
                GlassTextField(text: $addressText, mono: true)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("经跳板机")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text("只有这个地址不能直连时才需要打开")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.ink3)
                }
                Spacer()
                Toggle("", isOn: $useJump)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Color.ok)
            }

            if useJump {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledField(label: "跳板机") {
                        GlassTextField(
                            text: $jumpTarget,
                            mono: true,
                            placeholder: "user@bastion.example.com"
                        )
                    }
                    Text("API 地址是跳板机能访问的目标；本机会在 127.0.0.1 上开一个本地地址。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.ink3)
                        .fixedSize(horizontal: false, vertical: true)

                    DisclosureGroup(isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledField(label: "本地端口", hint: "自动") {
                                GlassNumberField(value: $localPort)
                            }
                            commandBlock
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("高级选项")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.ink3)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.border, lineWidth: 1)
                )
            }

            if let editError {
                Text(editError)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.bad)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("取消") {
                    editingConnection = false
                    editError = nil
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("完成") {
                    saveConnection()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
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
                    Clipboard.copy(draftBackend.sshCommand)
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
                .fill(Color.border)
                .frame(height: 1)

            Text(draftBackend.sshCommand)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.ink2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.border, lineWidth: 1)
        )
    }

    private var credentialsCard: some View {
        GlassCard(cornerRadius: 12, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("API Key")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text("可选。保存在 macOS 钥匙串，用于测试和客户端提示。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.ink3)
                }

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
                .frame(height: 33)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.border, lineWidth: 1)
                )

                HStack(spacing: 5) {
                    Image(systemName: "lock")
                        .font(.system(size: 10))
                    Text("不会写入配置文件或日志")
                        .font(.system(size: 9.5))
                }
                .foregroundStyle(Color.ink3)
            }
        }
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
                        .strokeBorder(Color.border, lineWidth: 1)
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
        .padding(.horizontal, 34)
        .padding(.vertical, 11)
        .background(Color.canvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
        }
    }

    private var connectionSummaryText: String {
        if backend.transport == .ssh {
            return "\(backend.host):\(backend.port) → 127.0.0.1:\(backend.localPort ?? 0)"
        }
        let defaultPort = (backend.schemeValue == "https" && backend.port == 443)
            || (backend.schemeValue == "http" && backend.port == 80)
        return "\(backend.schemeValue)://\(backend.urlHost)\(defaultPort ? "" : ":\(backend.port)")"
    }

    private var draftBackend: Backend {
        var draft = backend
        if let parsed = ServiceAddress.parse(addressText) {
            draft.scheme = parsed.scheme
            draft.host = parsed.host
            draft.port = parsed.port
            draft.apiPath = parsed.path
        }
        draft.transport = useJump ? .ssh : .direct
        draft.sshTarget = jumpTarget
        if useJump { draft.localPort = localPort }
        return draft
    }

    private func syncDrafts() {
        addressText = upstreamURL(backend)
        jumpTarget = backend.sshTarget
        useJump = backend.transport == .ssh
        localPort = backend.localPort ?? PortChecker.nextAvailable(
            startingAt: 18189,
            excluding: Set(model.backends.compactMap(\.localPort))
        )
    }

    private func beginEditing() {
        syncDrafts()
        editError = nil
        showAdvanced = false
        editingConnection = true
    }

    private func saveConnection() {
        guard let parsed = ServiceAddress.parse(addressText) else {
            editError = "地址格式不正确"
            return
        }
        var updated = backend
        updated.scheme = parsed.scheme
        updated.host = parsed.host
        updated.port = parsed.port
        updated.apiPath = parsed.path
        updated.transport = useJump ? .ssh : .direct
        updated.sshTarget = jumpTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.transport == .ssh {
            updated.localPort = localPort
        }
        do {
            updated = try updated.validated()
        } catch {
            editError = error.localizedDescription
            return
        }
        model.updateBackend(id: backend.id) { $0 = updated }
        editError = nil
        editingConnection = false
    }

    private func upstreamURL(_ backend: Backend) -> String {
        let defaultPort = (backend.schemeValue == "https" && backend.port == 443)
            || (backend.schemeValue == "http" && backend.port == 80)
        return "\(backend.schemeValue)://\(backend.urlHost)\(defaultPort ? "" : ":\(backend.port)")\(backend.apiPath)"
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { model.backend(id: backend.id)?.name ?? backend.name },
            set: { value in model.updateBackend(id: backend.id) { $0.name = value } }
        )
    }

    private var keyBinding: Binding<String> {
        Binding(
            get: { model.apiKey(for: backend.id) },
            set: { value in model.setAPIKey(value, for: backend.id) }
        )
    }
}

private struct EmptyDetailView: View {
    @ObservedObject var model: AppModel
    let add: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentSoft)
                Image(systemName: "link")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accent)
            }
            .frame(width: 52, height: 52)

            Text("还没有服务")
                .font(Typography.display(23))
                .foregroundStyle(Color.ink)

            Text("添加一个 API 地址就能开始。跳板机、本地端口这些高级选项可以稍后设置。")
                .font(.system(size: 11))
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Button {
                add()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("添加第一个服务")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
