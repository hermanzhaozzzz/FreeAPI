import Foundation

struct TunnelConfiguration: Decodable {
    let sshDestination: String
    let remoteHost: String
    let remotePort: Int
    let localPort: Int
    let apiPath: String

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FreeAPI/config.json")
    }

    static func load(from url: URL = fileURL) throws -> TunnelConfiguration {
        let configuration = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try configuration.validate()
        return configuration
    }

    func validate() throws {
        func matches(_ value: String, _ pattern: String) -> Bool {
            value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
        }
        guard matches(sshDestination, "^[A-Za-z0-9_][A-Za-z0-9_.@:-]*$") else {
            throw ConfigurationError.invalid("sshDestination 应为 SSH Host 别名或 user@hostname")
        }
        guard matches(remoteHost, "^[A-Za-z0-9:][A-Za-z0-9.:-]*$") else {
            throw ConfigurationError.invalid("remoteHost 应为主机名或 IP，不含协议和端口")
        }
        guard (1...65535).contains(remotePort), (1024...65535).contains(localPort) else {
            throw ConfigurationError.invalid("remotePort 范围为 1–65535；localPort 范围为 1024–65535")
        }
        guard matches(apiPath, "^(/[A-Za-z0-9._~-]+)*$") else {
            throw ConfigurationError.invalid("apiPath 应为 /v1 或空字符串，不带末尾斜杠")
        }
    }

    var endpoint: String { "http://127.0.0.1:\(localPort)\(apiPath)" }
    var forwardingArgument: String {
        let host = remoteHost.contains(":") ? "[\(remoteHost)]" : remoteHost
        return "127.0.0.1:\(localPort):\(host):\(remotePort)"
    }
}

enum ConfigurationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}
