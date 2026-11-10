import Foundation

func decode(_ changes: [String: Any] = [:]) throws -> TunnelConfiguration {
    var fields: [String: Any] = [
        "sshDestination": "user@bastion.example.com", "remoteHost": "api.internal.example.com",
        "remotePort": 8189, "localPort": 18189, "apiPath": "/v1"
    ]
    fields.merge(changes) { _, new in new }
    let config = try JSONDecoder().decode(TunnelConfiguration.self, from: JSONSerialization.data(withJSONObject: fields))
    try config.validate()
    return config
}

let config = try decode()
assert(config.endpoint == "http://127.0.0.1:18189/v1")
assert(config.forwardingArgument == "127.0.0.1:18189:api.internal.example.com:8189")
let ipv6 = try decode(["remoteHost": "2001:db8::1"])
assert(ipv6.forwardingArgument == "127.0.0.1:18189:[2001:db8::1]:8189")
for change: [String: Any] in [
    ["sshDestination": "-oProxyCommand=bad"], ["sshDestination": "user@host\n"],
    ["remoteHost": "host:80/other"], ["remoteHost": "http://host"],
    ["localPort": 80], ["localPort": 65536], ["remotePort": 0],
    ["apiPath": "/v1?secret=bad"], ["apiPath": "/v1/"], ["apiPath": "v1"]
] {
    do { _ = try decode(change); fatalError("Accepted invalid configuration: \(change)") }
    catch is ConfigurationError { }
}
print("PASS configuration validation, loopback forwarding, IPv6 target")
