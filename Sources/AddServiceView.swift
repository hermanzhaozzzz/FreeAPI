import SwiftUI

struct AddServiceView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var key = ""
    @State private var revealKey = false
    @State private var error: String?

    private var parsed: ServiceAddress? { ServiceAddress.parse(address) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 14) {
                LabeledField(label: "API 地址") {
                    GlassTextField(
                        text: $address,
                        mono: true,
                        placeholder: "https://api.example.com/v1"
                    )
                }
                Text("可以粘贴完整 URL；路径会自动识别，未写路径时默认 /v1。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.ink3)

                LabeledField(label: "API Key（可选）") {
                    HStack(spacing: 6) {
                        Group {
                            if revealKey {
                                TextField("sk-…", text: $key)
                            } else {
                                SecureField("sk-…", text: $key)
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
                            .fill(Color.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.border, lineWidth: 1)
                    )
                }

                preview

                Text("如果这个地址只能通过跳板机访问，添加后在服务详情的「连接」里打开「经跳板机」即可。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.ink3)
                    .fixedSize(horizontal: false, vertical: true)

                if let error {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.bad)
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("取消") {
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("添加并测试") {
                        add()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 2)
            }
            .padding(.top, 18)
        }
        .padding(22)
        .frame(width: 560)
        .background(Color.canvas)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("添加服务")
                    .font(Typography.display(20))
                    .foregroundStyle(Color.ink)
                Text("粘贴 API 地址即可。跳板机和高级选项可以稍后设置。")
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
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("将添加")
                .font(.system(size: 9))
                .foregroundStyle(Color.ink3)
            HStack(spacing: 7) {
                Text("直连")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accent)
                Text(parsed?.displayURL ?? "输入地址后显示客户端 Base URL")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(parsed == nil ? Color.ink3 : Color.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.border, lineWidth: 1)
        )
    }

    private func add() {
        do {
            _ = try model.addService(address: address, key: key)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
