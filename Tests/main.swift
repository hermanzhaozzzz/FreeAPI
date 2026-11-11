import Foundation
import Darwin

setbuf(stdout, nil)

let syncTestRoot = NSTemporaryDirectory() + "freeapi-config-store-\(ProcessInfo.processInfo.processIdentifier)"
let syncLocalDir = syncTestRoot + "/local"
let syncCloudRoot = syncTestRoot + "/icloud"
let syncCloudDir = syncCloudRoot + "/FreeAPI"
unsetenv("FREEAPI_CONFIG_DIR")
setenv("FREEAPI_LOCAL_DIR", syncLocalDir, 1)
setenv("FREEAPI_ICLOUD_DIR", syncCloudDir, 1)
setenv("FREEAPI_FORCE_ICLOUD", "1", 1)
let syncFileManager = FileManager.default
try? syncFileManager.createDirectory(atPath: syncCloudRoot, withIntermediateDirectories: true)
try? syncFileManager.createDirectory(atPath: syncLocalDir, withIntermediateDirectories: true)

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

// MARK: - config store / iCloud migration

let syncSeed = Backend(
    name: "同步测试",
    transport: .direct,
    scheme: "https",
    host: "api.example.com",
    port: 443,
    apiPath: "/v1",
    localPort: nil,
    sshTarget: "",
    enabled: false
)
let syncEncoder = JSONEncoder()
syncEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try! syncEncoder.encode(AppConfiguration(backends: [syncSeed]))
    .write(to: URL(fileURLWithPath: syncLocalDir + "/config.json"))

do {
    let loaded = try ConfigurationStore.load()
    check(loaded.configuration.backends.first?.name == "同步测试", "本机配置迁移到 iCloud")
    check(ConfigLocation.isUsingICloud, "当前使用 iCloud 位置")
    let cloudURL = URL(fileURLWithPath: syncCloudDir + "/config.json")
    check(syncFileManager.fileExists(atPath: cloudURL.path), "iCloud 配置文件已创建")
    check(syncFileManager.fileExists(atPath: syncLocalDir + "/config.json"), "本机配置保留为备份")
} catch {
    check(false, "iCloud 配置迁移失败：\(error.localizedDescription)")
}

do {
    var changed = try ConfigurationStore.load().configuration
    changed.backends[0].name = "同步已保存"
    let data = try ConfigurationStore.save(changed)
    check(!data.isEmpty, "iCloud 保存返回数据")
    let reopened = try ConfigurationStore.load()
    check(reopened.configuration.backends.first?.name == "同步已保存", "iCloud 保存后重新读取")
    check(ConfigurationStore.currentData() != nil, "iCloud 当前配置数据可读")
} catch {
    check(false, "iCloud 保存测试失败：\(error.localizedDescription)")
}

do {
    var newerBackend = syncSeed
    newerBackend.name = "本机更新"
    try syncEncoder.encode(AppConfiguration(backends: [newerBackend]))
        .write(to: URL(fileURLWithPath: syncLocalDir + "/config.json"))
    try syncFileManager.setAttributes(
        [.modificationDate: Date().addingTimeInterval(10)],
        ofItemAtPath: syncLocalDir + "/config.json"
    )
    let loaded = try ConfigurationStore.load()
    check(loaded.configuration.backends.first?.name == "本机更新", "较新的本机配置覆盖旧 iCloud 副本")
} catch {
    check(false, "较新本机配置迁移失败：\(error.localizedDescription)")
}

try? syncFileManager.removeItem(atPath: syncTestRoot)

if failures > 0 {
    fatalError("\(failures) model test(s) failed")
}
print("PASS models")
