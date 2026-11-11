import Foundation

struct ConfigBackup: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let summary: String
    let configuration: AppConfiguration
}

enum ConfigBackupStore {
    static let maxBackups = 20

    static var directoryURL: URL {
        ConfigLocation.defaultDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("backups.json")
    }

    static func load() -> [ConfigBackup] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backups = try? decoder.decode([ConfigBackup].self, from: data) else {
            return []
        }
        return Array(backups.prefix(maxBackups))
    }

    @discardableResult
    static func add(configuration: AppConfiguration, summary: String) -> [ConfigBackup] {
        var backups = load()
        if let latest = backups.first, latest.configuration == configuration {
            return backups
        }
        let entry = ConfigBackup(
            id: UUID(),
            createdAt: Date(),
            summary: summary,
            configuration: configuration
        )
        backups.insert(entry, at: 0)
        if backups.count > maxBackups {
            backups = Array(backups.prefix(maxBackups))
        }
        save(backups)
        return backups
    }

    private static func save(_ backups: [ConfigBackup]) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(backups)
            try data.write(to: fileURL, options: [.atomic])
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Backups are best-effort; the live config has already been saved.
        }
    }
}

enum ConfigurationDiff {
    static func summary(from old: AppConfiguration?, to new: AppConfiguration) -> String {
        guard let old else { return "创建配置" }
        if old == new { return "保存配置" }

        var parts: [String] = []
        if old.mode != new.mode {
            parts.append(new.mode == .single ? "切换为单路模式" : "切换为并行模式")
        }

        var oldMap: [UUID: Backend] = [:]
        for backend in old.backends { oldMap[backend.id] = backend }
        var newMap: [UUID: Backend] = [:]
        for backend in new.backends { newMap[backend.id] = backend }

        for backend in new.backends where oldMap[backend.id] == nil {
            parts.append("添加「\(displayName(backend))」")
        }
        for backend in old.backends where newMap[backend.id] == nil {
            parts.append("删除「\(displayName(backend))」")
        }

        for backend in new.backends {
            guard let previous = oldMap[backend.id], previous != backend else { continue }
            if onlyEnabledChanged(previous, backend) {
                parts.append(backend.enabled ? "启用「\(displayName(backend))」" : "停用「\(displayName(backend))」")
                continue
            }

            var fields: [String] = []
            if previous.name != backend.name { fields.append("名称") }
            if previous.transport != backend.transport { fields.append("连接方式") }
            if previous.scheme != backend.scheme { fields.append("协议") }
            if previous.host != backend.host { fields.append("服务器地址") }
            if previous.port != backend.port { fields.append("端口") }
            if previous.apiPath != backend.apiPath { fields.append("API 路径") }
            if previous.localPort != backend.localPort { fields.append("本地端口") }
            if previous.sshTarget != backend.sshTarget { fields.append("SSH 目标") }
            if previous.enabled != backend.enabled { fields.append("启用状态") }

            if !fields.isEmpty {
                let shown = fields.prefix(3).joined(separator: "、")
                    + (fields.count > 3 ? " 等" : "")
                parts.append("修改「\(displayName(backend))」：\(shown)")
            }
        }

        return parts.isEmpty ? "保存配置" : parts.joined(separator: "；")
    }

    private static func onlyEnabledChanged(_ old: Backend, _ new: Backend) -> Bool {
        var copy = old
        copy.enabled = new.enabled
        return copy == new
    }

    private static func displayName(_ backend: Backend) -> String {
        backend.name.isEmpty ? "未命名后端" : backend.name
    }
}
