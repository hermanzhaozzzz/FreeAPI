import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingAction: SettingsPendingAction?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    backendsSection
                    backupsSection
                    storageSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            footer
        }
        .frame(width: 760, height: 660)
        .background {
            ZStack {
                AuroraBackground()
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .bottom) {
            ToastOverlay(text: model.toast)
                .padding(.bottom, 58)
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .alert(item: $pendingAction) { action in
            switch action {
            case .delete(let backend):
                return Alert(
                    title: Text("删除后端？"),
                    message: Text("“\(backend.name)”和它在钥匙串中的 API Key 会一起删除。"),
                    primaryButton: .destructive(Text("删除")) {
                        model.deleteBackend(backend.id)
                    },
                    secondaryButton: .cancel()
                )
            case .restore(let backup):
                return Alert(
                    title: Text("恢复这份备份？"),
                    message: Text("\(model.backupTimeText(backup.createdAt)) · \(backup.summary)\n当前配置会先保存为一份备份。"),
                    primaryButton: .destructive(Text("恢复")) {
                        model.restoreBackup(backup)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accent.opacity(0.16))
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("高级设置")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("集中管理所有后端和配置存储")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ink3)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle())
            .help("关闭")
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    private var backendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("后端管理")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text("集中添加、启停和删除；SSH 隧道与直连都在这里。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.ink3)
                }
                Spacer(minLength: 8)
                HStack(spacing: 7) {
                    Button {
                        add(.ssh)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                            Text("添加 SSH")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        add(.direct)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                            Text("添加直连")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            GlassCard(cornerRadius: 14, padding: 0) {
                if model.backends.isEmpty {
                    VStack(spacing: 6) {
                        Text("还没有后端")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.ink2)
                        Text("用右上角的按钮添加 SSH 隧道或直连后端。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.ink3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.backends.enumerated()), id: \.element.id) { index, backend in
                            backendRow(backend)
                            if index < model.backends.count - 1 {
                                Rectangle()
                                    .fill(Color.hairline)
                                    .frame(height: 1)
                                    .padding(.leading, 42)
                            }
                        }
                    }
                }
            }

            Text("“编辑”会回到主窗口修改地址、协议、本地端口和 API Key。")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.ink3)
        }
    }

    private func backendRow(_ backend: Backend) -> some View {
        HStack(spacing: 10) {
            StatusDot(state: model.state(for: backend))

            VStack(alignment: .leading, spacing: 3) {
                Text(backend.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    TagPill(transport: backend.transport)
                    Text(backend.host.isEmpty ? "未填写地址" : backend.upstreamAddress)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.ink3)
                        .lineLimit(1)
                    if backend.transport == .ssh {
                        Text("→ \(backend.localAddress)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color.ink3)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            Text(model.latencyText(for: backend))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(latencyColor(backend))
                .frame(width: 50, alignment: .trailing)

            Toggle("", isOn: Binding(
                get: { model.backend(id: backend.id)?.enabled ?? backend.enabled },
                set: { model.setEnabled($0, for: backend.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Color.ok)

            Button("编辑") {
                model.select(backend.id)
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                pendingAction = .delete(backend)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.bad)
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
            .help("删除 \(backend.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("配置存储")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("配置会在修改后自动保存到当前位置；备份保留在本机。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ink3)
            }

            GlassCard(cornerRadius: 14, padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: model.isUsingICloudConfig ? "icloud" : "folder")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.accent)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accent.opacity(0.10))
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前位置")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Color.ink3)
                            Text(model.configLocationLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.ink)
                            Text(abbreviatedPath)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(Color.ink3)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                        Text("上次备份：\(model.lastBackupText)")
                            .font(.system(size: 9.5))
                    }
                    .foregroundStyle(Color.ink3)

                    HStack(spacing: 7) {
                        if !model.isUsingICloudConfig {
                            Button("使用 iCloud Drive") {
                                model.useICloudLocation()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        if !model.isUsingLocalConfig {
                            Button("使用本机默认位置") {
                                model.useLocalLocation()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        Button("选择其它文件夹…") {
                            model.chooseConfigFolder()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Spacer()
                    }

                    HStack(spacing: 7) {
                        Button {
                            model.reloadConfiguration()
                        } label: {
                            Label("重新载入", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Button {
                            ConfigurationStore.revealInFinder()
                        } label: {
                            Label("在 Finder 中显示", systemImage: "folder")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Spacer()
                    }

                    Text("API Key 保存在钥匙串；开启 iCloud 钥匙串后可在多台 Mac 共用。多端同时修改采用最后写入覆盖。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var backupsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("配置备份")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text("每次保存记录改动，最多保留 \(ConfigBackupStore.maxBackups) 份；恢复前会先保存当前配置。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.ink3)
                }
                Spacer(minLength: 8)
                Text("上次备份：\(model.lastBackupText)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.ink3)
            }

            GlassCard(cornerRadius: 14, padding: 0) {
                if model.backups.isEmpty {
                    Text("暂无备份，修改配置后会自动生成。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(model.backups.enumerated()), id: \.element.id) { index, backup in
                                backupRow(backup)
                                if index < model.backups.count - 1 {
                                    Rectangle()
                                        .fill(Color.hairline)
                                        .frame(height: 1)
                                        .padding(.leading, 42)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 190)
                }
            }

            Text("API Key 不会随备份恢复；已删除的 Key 需要重新填写。")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.ink3)
        }
    }

    private func backupRow(_ backup: ConfigBackup) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.backupTimeText(backup.createdAt))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text(backup.summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ink3)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button("恢复") {
                pendingAction = .restore(backup)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
            HStack {
                Text("修改会在约 1.5 秒后保存并自动备份")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.ink3)
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private var abbreviatedPath: String {
        (ConfigLocation.activeDirectory.path as NSString).abbreviatingWithTildeInPath
    }

    private func add(_ transport: BackendTransport) {
        model.addBackend(transport: transport)
        dismiss()
    }

    private func latencyColor(_ backend: Backend) -> Color {
        switch model.state(for: backend) {
        case .connected: return .ok
        case .connecting, .degraded: return .warn
        case .error: return .bad
        case .off: return .ink3
        }
    }
}

private enum SettingsPendingAction: Identifiable {
    case delete(Backend)
    case restore(ConfigBackup)

    var id: String {
        switch self {
        case .delete(let backend): return "delete-\(backend.id.uuidString)"
        case .restore(let backup): return "restore-\(backup.id.uuidString)"
        }
    }
}
