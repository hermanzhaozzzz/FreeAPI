import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingRestore: ConfigBackup?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    storageSection
                    backupsSection
                    modeSection
                }
                .padding(22)
            }
            footer
        }
        .frame(width: 680, height: 620)
        .background(Color.canvas)
        .overlay(alignment: .bottom) {
            ToastOverlay(text: model.toast)
                .padding(.bottom, 58)
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .alert(item: $pendingRestore) { backup in
            Alert(
                title: Text("恢复这份备份？"),
                message: Text("\(model.backupTimeText(backup.createdAt)) · \(backup.summary)\n当前配置会先保存为一份备份。"),
                primaryButton: .destructive(Text("恢复")) {
                    model.restoreBackup(backup)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("设置")
                    .font(Typography.display(20))
                    .foregroundStyle(Color.ink)
                Text("配置存储、备份和运行模式这些不常改的选项放在这里。")
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
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("配置存储")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("配置会在修改后自动保存到当前位置；备份保留在本机。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ink3)
            }

            GlassCard(cornerRadius: 12, padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: model.isUsingICloudConfig ? "icloud" : "folder")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.accent)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentSoft)
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
                        .font(.system(size: 12.5, weight: .semibold))
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

            GlassCard(cornerRadius: 12, padding: 0) {
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
                                        .fill(Color.border)
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
                pendingRestore = backup
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("运行模式")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("默认所有启用的服务同时运行。需要时再切到单路。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ink3)
            }

            GlassCard(cornerRadius: 12, padding: 14) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.mode == .parallel ? "同时运行多个服务" : "只运行当前服务")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.ink)
                        Text(model.mode == .parallel ? "每个服务使用自己的本地端口" : "切换服务时自动停用其它服务")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.ink3)
                    }
                    Spacer()
                    Picker("", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                        Text("同时").tag(RunMode.parallel)
                        Text("单路").tag(RunMode.single)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 120)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.border)
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
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
    }

    private var abbreviatedPath: String {
        (ConfigLocation.activeDirectory.path as NSString).abbreviatingWithTildeInPath
    }
}
