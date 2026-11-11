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
    static var directoryURL: URL { ConfigLocation.activeDirectory }
    static var fileURL: URL { directoryURL.appendingPathComponent("config.json") }
    static var legacyBackupURL: URL { directoryURL.appendingPathComponent("config.v1.backup.json") }

    static func load() throws -> (configuration: AppConfiguration, migrated: Bool) {
        migrateLocalConfigIfNeeded()

        let directory = ConfigLocation.activeDirectory
        let url = directory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigurationStoreError.missing
        }

        let data: Data
        do {
            data = try coordinatedRead(url)
        } catch {
            throw ConfigurationStoreError.unreadable(error.localizedDescription)
        }

        do {
            return try decodeWithLegacy(data)
        } catch {
            if ConfigLocation.isUsingICloud {
                let localURL = ConfigLocation.defaultDirectory.appendingPathComponent("config.json")
                if let localData = try? coordinatedRead(localURL),
                   let localResult = try? decodeWithLegacy(localData) {
                    ConfigLocation.fallbackToLocalForLaunch(reason: "iCloud 配置无法读取，已临时使用本机配置")
                    return localResult
                }
            }
            throw ConfigurationStoreError.unreadable("JSON 格式不正确")
        }
    }

    static func decode(_ data: Data) throws -> AppConfiguration {
        let decoder = JSONDecoder()
        if let configuration = try? decoder.decode(AppConfiguration.self, from: data) {
            return configuration
        }
        if let legacy = try? decoder.decode(LegacyConfiguration.self, from: data) {
            return AppConfiguration(backends: [legacy.migratedBackend]).sanitized()
        }
        throw ConfigurationStoreError.unreadable("JSON 格式不正确")
    }

    private static func decodeWithLegacy(_ data: Data) throws -> (configuration: AppConfiguration, migrated: Bool) {
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

    @discardableResult
    static func save(_ configuration: AppConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)

        let manager = FileManager.default
        let directory = ConfigLocation.activeDirectory
        if !manager.fileExists(atPath: directory.path) {
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let url = directory.appendingPathComponent("config.json")
        try coordinatedWrite(data, to: url)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return data
    }

    static func currentData() -> Data? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? coordinatedRead(url)
    }

    static func revealInFinder() {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directoryURL.path) {
            try? manager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(directoryURL)
    }

    private static func migrateLocalConfigIfNeeded() {
        guard ConfigLocation.isUsingICloud else { return }
        let manager = FileManager.default
        let target = fileURL
        guard !manager.fileExists(atPath: target.path) else { return }

        let source = ConfigLocation.defaultDirectory.appendingPathComponent("config.json")
        guard manager.fileExists(atPath: source.path) else { return }

        do {
            try manager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try coordinatedRead(source)
            try coordinatedWrite(data, to: target)
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } catch {
            ConfigLocation.fallbackToLocalForLaunch(reason: "无法写入 iCloud 配置，已临时使用本机配置")
        }
    }

    private static func backupLegacy(_ data: Data) throws {
        let manager = FileManager.default
        let url = legacyBackupURL
        guard !manager.fileExists(atPath: url.path) else { return }
        try coordinatedWrite(data, to: url)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ConfigurationStoreError.unreadable("无法读取文件") }
        return try result.get()
    }

    private static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        let options: NSFileCoordinator.WritingOptions = FileManager.default.fileExists(atPath: url.path)
            ? .forReplacing
            : []
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { writeURL in
            do {
                try data.write(to: writeURL, options: [.atomic])
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
