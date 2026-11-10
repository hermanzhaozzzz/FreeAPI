import Foundation

setbuf(stdout, nil)

var failures = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("PASS \(message)")
    } else {
        failures += 1
        print("FAIL \(message)")
    }
}

let ssh = Backend(
    name: "上海 GPU 集群",
    transport: .ssh,
    scheme: "http",
    host: "api.sh-gpu.example.com",
    port: 8189,
    apiPath: "/v1",
    localPort: 18189,
    sshTarget: "hnzhao@bastion.example.com",
    enabled: true
)
check(ssh.endpoint == "http://127.0.0.1:18189/v1", "SSH 本地地址")
check(ssh.healthURL == "http://127.0.0.1:18189/v1/models", "SSH 健康检查")
check(ssh.forwardingArgument == "127.0.0.1:18189:api.sh-gpu.example.com:8189", "SSH 转发参数")
check(
    ssh.sshCommand.contains("-L 127.0.0.1:18189:api.sh-gpu.example.com:8189 hnzhao@bastion.example.com"),
    "SSH 命令"
)

let ipv6 = Backend(
    name: "IPv6",
    transport: .ssh,
    scheme: "http",
    host: "2001:db8::1",
    port: 8080,
    apiPath: "/v1",
    localPort: 18190,
    sshTarget: "u@b",
    enabled: false
)
check(ipv6.forwardingArgument == "127.0.0.1:18190:[2001:db8::1]:8080", "IPv6 转发")

let direct = Backend(
    name: "DeepSeek",
    transport: .direct,
    scheme: "https",
    host: "api.deepseek.com",
    port: 443,
    apiPath: "/v1",
    localPort: nil,
    sshTarget: "",
    enabled: false
)
check(direct.endpoint == "https://api.deepseek.com/v1", "直连默认端口")
check(direct.healthURL == "https://api.deepseek.com/v1/models", "直连健康检查")

var directPort = direct
directPort.port = 8443
check(directPort.endpoint == "https://api.deepseek.com:8443/v1", "直连非默认端口")

var emptyPath = ssh
emptyPath.apiPath = ""
check(emptyPath.endpoint == "http://127.0.0.1:18189", "空 API 路径")
check(emptyPath.healthURL == "http://127.0.0.1:18189/models", "空路径健康检查")

check((try? ssh.validated()) != nil, "合法 SSH 配置")
check((try? direct.validated()) != nil, "合法直连配置")

var badTarget = ssh
badTarget.sshTarget = "-oProxyCommand=bad"
check((try? badTarget.validated()) == nil, "拒绝参数注入的 SSH 目标")

var badNewline = ssh
badNewline.sshTarget = "user@host\n-oProxyCommand=bad"
check((try? badNewline.validated()) == nil, "拒绝换行的 SSH 目标")

var trimmedTarget = ssh
trimmedTarget.sshTarget = "user@host\n"
check((try? trimmedTarget.validated())?.sshTarget == "user@host", "修剪 SSH 目标空白")

var badHostScheme = ssh
badHostScheme.host = "http://host"
check((try? badHostScheme.validated()) == nil, "拒绝带协议的服务器地址")

var badHostPath = ssh
badHostPath.host = "host:80/other"
check((try? badHostPath.validated()) == nil, "拒绝带路径的服务器地址")

var badLocal = ssh
badLocal.localPort = 80
check((try? badLocal.validated()) == nil, "拒绝低本地端口")

var badPort = ssh
badPort.port = 0
check((try? badPort.validated()) == nil, "拒绝零端口")

var badQuery = ssh
badQuery.apiPath = "/v1?secret=bad"
check((try? badQuery.validated()) == nil, "拒绝 API 路径参数")

var badSlash = ssh
badSlash.apiPath = "/v1/"
check((try? badSlash.validated()) == nil, "拒绝末尾斜杠")

var badRelative = ssh
badRelative.apiPath = "v1"
check((try? badRelative.validated()) == nil, "拒绝相对 API 路径")

var badName = ssh
badName.name = "   "
check((try? badName.validated()) == nil, "拒绝空名称")

var badScheme = direct
badScheme.scheme = "ftp"
check((try? badScheme.validated()) == nil, "拒绝未知协议")

var duplicateA = ssh
duplicateA.id = UUID()
duplicateA.localPort = 18189
var duplicateB = ssh
duplicateB.id = UUID()
duplicateB.localPort = 18189
let sanitized = AppConfiguration(backends: [duplicateA, duplicateB]).sanitized()
let ports = sanitized.backends.compactMap(\.localPort)
check(ports.count == 2 && Set(ports).count == 2, "本地端口唯一化")

var noPort = ssh
noPort.localPort = nil
let assigned = AppConfiguration(backends: [noPort]).sanitized()
check(assigned.backends[0].localPort != nil, "补全缺失的本地端口")

let legacyJSON = """
{"sshDestination":"u@b","remoteHost":"api.internal","remotePort":8189,"localPort":18189,"apiPath":"/v1"}
""".data(using: .utf8)!
let legacy = try! JSONDecoder().decode(LegacyConfiguration.self, from: legacyJSON)
check(legacy.migratedBackend.transport == .ssh, "旧配置迁移为 SSH")
check(legacy.migratedBackend.enabled, "旧配置迁移后启用")
check(legacy.migratedBackend.endpoint == "http://127.0.0.1:18189/v1", "旧配置迁移地址")

let original = AppConfiguration(mode: .single, backends: [ssh, direct])
let encoded = try! JSONEncoder().encode(original)
let decoded = try! JSONDecoder().decode(AppConfiguration.self, from: encoded)
check(decoded == original, "v2 配置往返")

if failures > 0 {
    fatalError("\(failures) model test(s) failed")
}
print("PASS models")
