import Foundation
import AppKit

enum ConfigurationStoreError: LocalizedError {
    case missing
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .missing:
            return "还没有配置文件。添加一个后端后会自动保存。"
        case .unreadable(let message):
            return "配置文件无法读取：\(message)"
        }
    }
}

enum ConfigurationStore {
    static var directoryURL: URL {
        if let override = ProcessInfo.processInfo.environment["FREEAPI_CONFIG_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FreeAPI", isDirectory: true)
    }

    static var fileURL: URL { directoryURL.appendingPathComponent("config.json") }
    static var legacyBackupURL: URL { directoryURL.appendingPathComponent("config.v1.backup.json") }

    static func load() throws -> (configuration: AppConfiguration, migrated: Bool) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ConfigurationStoreError.missing
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ConfigurationStoreError.unreadable(error.localizedDescription)
        }

        let decoder = JSONDecoder()
        if let configuration = try? decoder.decode(AppConfiguration.self, from: data) {
            return (configuration, false)
        }
        if let legacy = try? decoder.decode(LegacyConfiguration.self, from: data) {
            let configuration = AppConfiguration(backends: [legacy.migratedBackend]).sanitized()
            try? backupLegacy(data)
            return (configuration, true)
        }
        throw ConfigurationStoreError.unreadable("JSON 格式不正确")
    }

    static func save(_ configuration: AppConfiguration) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directoryURL.path) {
            try manager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: [.atomic])
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func backupLegacy(_ data: Data) throws {
        guard !FileManager.default.fileExists(atPath: legacyBackupURL.path) else { return }
        try data.write(to: legacyBackupURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: legacyBackupURL.path
        )
    }

    static func revealInFinder() {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directoryURL.path) {
            try? manager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(directoryURL)
    }
}
