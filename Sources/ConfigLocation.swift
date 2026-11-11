import Foundation
import AppKit

enum ConfigLocationError: LocalizedError {
    case iCloudUnavailable
    case customFolderUnavailable

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive 当前不可用，已保留本机位置"
        case .customFolderUnavailable:
            return "这个文件夹不可用"
        }
    }
}

struct ConfigLocationSnapshot {
    let activeDirectory: URL
    let useLocal: Bool
    let bookmark: Data?
    let path: String?
    let fallbackWarning: String?
}

enum ConfigLocation {
    private static let useLocalKey = "FreeAPI.useLocalConfig"
    private static let bookmarkKey = "FreeAPI.configFolderBookmark"
    private static let pathKey = "FreeAPI.configFolderPath"

    private(set) static var activeDirectory: URL = resolveActiveDirectory()
    private(set) static var fallbackWarning: String?

    static var defaultDirectory: URL {
        if let override = environment("FREEAPI_LOCAL_DIR") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FreeAPI", isDirectory: true)
    }

    static var iCloudDirectory: URL {
        if let override = environment("FREEAPI_ICLOUD_DIR") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/FreeAPI", isDirectory: true)
    }

    static var isUsingICloud: Bool {
        samePath(activeDirectory, iCloudDirectory)
    }

    static var isUsingCustom: Bool {
        guard !isUsingICloud else { return false }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: useLocalKey) { return false }
        return defaults.data(forKey: bookmarkKey) != nil || defaults.string(forKey: pathKey) != nil
    }

    static var isUsingLocal: Bool {
        !isUsingICloud && !isUsingCustom
    }

    static var displayName: String {
        if isUsingICloud { return "iCloud Drive/FreeAPI" }
        if isUsingCustom {
            return (activeDirectory.path as NSString).abbreviatingWithTildeInPath
        }
        return "本机 Application Support"
    }

    static func resolveActiveDirectory() -> URL {
        if let override = environment("FREEAPI_CONFIG_DIR") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if environment("FREEAPI_FORCE_ICLOUD") != nil {
            return prepareICloudDirectory() ?? defaultDirectory
        }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: useLocalKey) {
            return defaultDirectory
        }
        if let custom = resolveCustomDirectory() {
            return custom
        }
        if let iCloud = prepareICloudDirectory() {
            return iCloud
        }
        return defaultDirectory
    }

    private static func prepareICloudDirectory() -> URL? {
        let manager = FileManager.default
        if environment("FREEAPI_ICLOUD_DIR") != nil {
            do {
                try manager.createDirectory(at: iCloudDirectory, withIntermediateDirectories: true)
                return iCloudDirectory
            } catch {
                return nil
            }
        }

        let root = iCloudDirectory.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              manager.isWritableFile(atPath: root.path) else {
            return nil
        }
        do {
            try manager.createDirectory(at: iCloudDirectory, withIntermediateDirectories: true)
            return iCloudDirectory
        } catch {
            return nil
        }
    }

    static func withActiveDirectory<T>(_ body: (URL) throws -> T) rethrows -> T {
        let directory = activeDirectory
        let scoped = directory.startAccessingSecurityScopedResource()
        defer {
            if scoped { directory.stopAccessingSecurityScopedResource() }
        }
        return try body(directory)
    }

    static func useLocal() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: useLocalKey)
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: pathKey)
        activeDirectory = defaultDirectory
        fallbackWarning = nil
    }

    static func useICloud() throws {
        guard let directory = prepareICloudDirectory() else {
            throw ConfigLocationError.iCloudUnavailable
        }
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: useLocalKey)
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: pathKey)
        activeDirectory = directory
        fallbackWarning = nil
    }

    static func setCustomFolder(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ConfigLocationError.customFolderUnavailable
        }
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let defaults = UserDefaults.standard
        if let bookmark {
            defaults.set(bookmark, forKey: bookmarkKey)
        } else {
            defaults.removeObject(forKey: bookmarkKey)
        }
        defaults.set(url.path, forKey: pathKey)
        defaults.set(false, forKey: useLocalKey)
        activeDirectory = url
        fallbackWarning = nil
    }

    private static func resolveCustomDirectory() -> URL? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url
            }
        }
        if let path = defaults.string(forKey: pathKey) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    static func snapshot() -> ConfigLocationSnapshot {
        let defaults = UserDefaults.standard
        return ConfigLocationSnapshot(
            activeDirectory: activeDirectory,
            useLocal: defaults.bool(forKey: useLocalKey),
            bookmark: defaults.data(forKey: bookmarkKey),
            path: defaults.string(forKey: pathKey),
            fallbackWarning: fallbackWarning
        )
    }

    static func restore(_ snapshot: ConfigLocationSnapshot) {
        let defaults = UserDefaults.standard
        defaults.set(snapshot.useLocal, forKey: useLocalKey)
        if let bookmark = snapshot.bookmark {
            defaults.set(bookmark, forKey: bookmarkKey)
        } else {
            defaults.removeObject(forKey: bookmarkKey)
        }
        if let path = snapshot.path {
            defaults.set(path, forKey: pathKey)
        } else {
            defaults.removeObject(forKey: pathKey)
        }
        activeDirectory = snapshot.activeDirectory
        fallbackWarning = snapshot.fallbackWarning
    }

    static func fallbackToLocalForLaunch(reason: String) {
        activeDirectory = defaultDirectory
        fallbackWarning = reason
    }

    private static func environment(_ name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func samePath(_ first: URL, _ second: URL) -> Bool {
        first.standardizedFileURL.path == second.standardizedFileURL.path
    }
}
