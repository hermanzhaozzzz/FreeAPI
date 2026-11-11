import Foundation
import Darwin

enum BackendTransport: String, Codable, CaseIterable, Identifiable {
    case ssh
    case direct

    var id: String { rawValue }
    var label: String { self == .ssh ? "SSH 隧道" : "直连" }
    var shortLabel: String { self == .ssh ? "SSH" : "直连" }
}

enum RunMode: String, Codable, CaseIterable, Identifiable {
    case parallel
    case single

    var id: String { rawValue }
    var label: String { self == .parallel ? "并行" : "单路" }
    var note: String {
        self == .parallel
            ? "每个后端使用独立本地端口，可同时提供。"
            : "同一时间只运行一个后端，切换时自动停用其它后端。"
    }
}

struct Backend: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var transport: BackendTransport
    var scheme: String
    var host: String
    var port: Int
    var apiPath: String
    var localPort: Int?
    var sshTarget: String
    var enabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "新后端",
        transport: BackendTransport = .ssh,
        scheme: String = "http",
        host: String = "",
        port: Int = 8080,
        apiPath: String = "/v1",
        localPort: Int? = nil,
        sshTarget: String = "",
        enabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.scheme = scheme
        self.host = host
        self.port = port
        self.apiPath = apiPath
        self.localPort = localPort
        self.sshTarget = sshTarget
        self.enabled = enabled
    }

    var schemeValue: String { scheme.lowercased() == "https" ? "https" : "http" }
    var urlHost: String { host.contains(":") ? "[\(host)]" : host }
    var upstreamAddress: String { "\(host):\(port)" }
    var localAddress: String {
        if transport == .ssh, let localPort { return "127.0.0.1:\(localPort)" }
        return host
    }

    var endpoint: String {
        switch transport {
        case .ssh:
            return "http://127.0.0.1:\(localPort ?? 0)\(apiPath)"
        case .direct:
            let defaultPort = (schemeValue == "https" && port == 443) || (schemeValue == "http" && port == 80)
            return "\(schemeValue)://\(urlHost)\(defaultPort ? "" : ":\(port)")\(apiPath)"
        }
    }

    var healthURL: String { endpoint + "/models" }

    var forwardingArgument: String {
        let destination = host.contains(":") ? "[\(host)]" : host
        return "127.0.0.1:\(localPort ?? 0):\(destination):\(port)"
    }

    var sshCommand: String {
        "ssh -NT -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=10"
            + " -o StrictHostKeyChecking=yes -L \(forwardingArgument) \(sshTarget)"
    }

    func validated() throws -> Backend {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.scheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        result.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        result.apiPath = apiPath.trimmingCharacters(in: .whitespacesAndNewlines)
        result.sshTarget = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.name.isEmpty, result.name.count <= 80,
              !result.name.contains(where: { $0.isNewline }) else {
            throw BackendError.invalid("名称需要 1–80 个字符，且不能换行")
        }
        guard ["http", "https"].contains(result.scheme) else {
            throw BackendError.invalid("协议只能是 http 或 https")
        }
        guard Self.matches(result.host, "^[A-Za-z0-9:][A-Za-z0-9.:-]*$"),
              !result.host.contains("://"), !result.host.contains("/"),
              !result.host.contains("?"), !result.host.contains("#") else {
            throw BackendError.invalid("服务器地址只填主机名或 IP，不含协议和路径")
        }
        guard (1...65535).contains(result.port) else {
            throw BackendError.invalid("端口范围为 1–65535")
        }
        guard Self.matches(result.apiPath, "^(/[A-Za-z0-9._~-]+)*$"), result.apiPath.count <= 512 else {
            throw BackendError.invalid("API 路径应类似 /v1 或为空，不带末尾斜杠和参数")
        }
        if result.transport == .ssh {
            guard Self.matches(result.sshTarget, "^[A-Za-z0-9_][A-Za-z0-9_.@:-]*$") else {
                throw BackendError.invalid("SSH 目标应为 user@host 或 ~/.ssh/config 中的 Host 别名")
            }
            guard let localPort = result.localPort, (1024...65535).contains(localPort) else {
                throw BackendError.invalid("本地端口范围为 1024–65535")
            }
        }
        return result
    }

    var isReady: Bool { (try? validated()) != nil }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        guard let range = value.range(of: pattern, options: .regularExpression) else { return false }
        return range == value.startIndex..<value.endIndex
    }
}

enum BackendError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}

struct ServiceAddress {
    let scheme: String
    let host: String
    let port: Int
    let path: String

    static func parse(_ raw: String) -> ServiceAddress? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) == nil {
            value = "https://" + value
        }
        guard let components = URLComponents(string: value),
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        let scheme = components.scheme?.lowercased() == "http" ? "http" : "https"
        var path = components.path
        if path.isEmpty || path == "/" { path = "/v1" }
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        let port = components.port ?? (scheme == "https" ? 443 : 80)
        guard (1...65535).contains(port) else { return nil }
        return ServiceAddress(scheme: scheme, host: host, port: port, path: path)
    }

    var displayURL: String {
        let defaultPort = (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
        return "\(scheme)://\(host)\(defaultPort ? "" : ":\(port)")\(path)"
    }
}

struct AppConfiguration: Codable, Equatable {
    static let currentVersion = 2

    var version: Int
    var mode: RunMode
    var backends: [Backend]

    init(version: Int = AppConfiguration.currentVersion, mode: RunMode = .parallel, backends: [Backend] = []) {
        self.version = version
        self.mode = mode
        self.backends = backends
    }

    enum CodingKeys: String, CodingKey {
        case version
        case mode
        case backends
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        mode = try container.decodeIfPresent(RunMode.self, forKey: .mode) ?? .parallel
        backends = try container.decode([Backend].self, forKey: .backends)
    }

    /// Makes local ports unique without probing the network, so it is deterministic.
    func sanitized() -> AppConfiguration {
        var result = self
        var used = Set<Int>()
        var next = 18189
        for index in result.backends.indices {
            guard result.backends[index].transport == .ssh else { continue }
            var candidate = result.backends[index].localPort
            if candidate == nil || !(1024...65535).contains(candidate!) || used.contains(candidate!) {
                while used.contains(next) || !(1024...65535).contains(next) { next += 1 }
                candidate = next
            }
            result.backends[index].localPort = candidate
            used.insert(candidate!)
        }
        return result
    }

    func backend(id: UUID) -> Backend? { backends.first { $0.id == id } }

    func index(id: UUID) -> Int? { backends.firstIndex { $0.id == id } }
}

struct LegacyConfiguration: Decodable {
    let sshDestination: String
    let remoteHost: String
    let remotePort: Int
    let localPort: Int
    let apiPath: String

    var migratedBackend: Backend {
        Backend(
            name: remoteHost,
            transport: .ssh,
            scheme: "http",
            host: remoteHost,
            port: remotePort,
            apiPath: apiPath,
            localPort: localPort,
            sshTarget: sshDestination,
            enabled: true
        )
    }
}

enum PortChecker {
    static func isAvailable(_ port: Int) -> Bool {
        guard (1...65535).contains(port) else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    static func nextAvailable(startingAt start: Int = 18189, excluding: Set<Int> = []) -> Int {
        var port = max(1024, start)
        while port <= 65535 {
            if !excluding.contains(port) && isAvailable(port) { return port }
            port += 1
        }
        return start
    }
}

enum ConnectionState: String, Equatable {
    case off
    case connecting
    case connected
    case degraded
    case error

    var label: String {
        switch self {
        case .off: return "未启用"
        case .connecting: return "正在连接"
        case .connected: return "已连接"
        case .degraded: return "上游异常"
        case .error: return "连接异常"
        }
    }
}

struct BackendRuntime: Equatable {
    var state: ConnectionState = .off
    var latency: Int?
    var httpStatus: Int?
    var lastChecked: Date?
    var history: [Int] = []
    var errorMessage: String?
    var consecutiveFailures: Int = 0
    var log: String = ""
}
