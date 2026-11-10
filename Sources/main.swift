import AppKit
import Foundation
import Network
import Darwin

final class TunnelApp: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let stateItem = NSMenuItem(title: "正在连接…", action: nil, keyEquivalent: "")
    private let detailItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "断开", action: #selector(toggle), keyEquivalent: "")
    private var process: Process?
    private var pipe: Pipe?
    private var retry: DispatchWorkItem?
    private var timer: Timer?
    private var request: URLSessionDataTask?
    private var generation = 0
    private var wanted = true
    private var quitting = false
    private var failures = 0
    private var attempts = 0
    private var recentLog = ""
    private var currentState = "正在连接"
    private var terminationSignal: DispatchSourceSignal?
    private let monitor = NWPathMonitor()
    private let configuration: TunnelConfiguration
    private var endpoint: String { configuration.endpoint }

    init(configuration: TunnelConfiguration) {
        self.configuration = configuration
        super.init()
    }
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 6
        config.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0, "ProxyAutoConfigEnable": 0]
        return URLSession(configuration: config)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch must not create a competing tunnel.
        if NSRunningApplication.runningApplications(withBundleIdentifier: "local.freeapi").count > 1 {
            NSApp.terminate(nil)
            return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(stateItem)
        menu.addItem(detailItem)
        menu.addItem(.separator())
        let address = NSMenuItem(title: "复制 API 地址", action: #selector(copyAddress), keyEquivalent: "")
        address.target = self
        menu.addItem(address)
        let reconnect = NSMenuItem(title: "重新连接", action: #selector(reconnect), keyEquivalent: "r")
        reconnect.target = self
        menu.addItem(reconnect)
        toggleItem.target = self
        menu.addItem(toggleItem)
        let diagnostics = NSMenuItem(title: "连接详情…", action: #selector(showDetails), keyEquivalent: "")
        diagnostics.target = self
        menu.addItem(diagnostics)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出并关闭隧道", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        signal(SIGTERM, SIG_IGN)
        terminationSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminationSignal?.setEventHandler { NSApp.terminate(nil) }
        terminationSignal?.resume()
        setState("正在连接", symbol: "arrow.triangle.2.circlepath", detail: "SSH → 模型接口")
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self, self.wanted, !self.quitting else { return }
                if path.status == .satisfied && self.process == nil {
                    self.retry?.cancel()
                    self.retry = nil
                    self.connect()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "freeapi.network"))
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.checkHealth() }
        connect()
    }

    private func setState(_ state: String, symbol: String, detail: String) {
        currentState = state
        stateItem.title = state
        detailItem.title = detail
        item?.button?.image = NSImage(systemSymbolName: "link", accessibilityDescription: "FreeAPI · \(state)")?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        item?.button?.image?.isTemplate = true
        let color: NSColor = state == "已连接" ? .systemGreen : (wanted ? .systemOrange : .tertiaryLabelColor)
        item?.button?.attributedTitle = NSAttributedString(string: " ●", attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 8, weight: .medium)])
        item?.button?.toolTip = "FreeAPI · \(state)\n\(endpoint)"
        toggleItem.title = wanted ? "断开连接" : "连接"
    }

    private func portAvailable() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(configuration.localPort).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private func connect() {
        guard wanted, !quitting, process == nil else { return }
        retry?.cancel()
        retry = nil
        guard portAvailable() else {
            setState("端口被占用", symbol: "exclamationmark.triangle", detail: "\(configuration.localPort) 已被其他程序使用")
            scheduleRetry()
            return
        }
        generation += 1
        let token = generation
        failures = 0
        setState("正在连接", symbol: "arrow.triangle.2.circlepath", detail: "正在建立 SSH 隧道…")
        let child = Process()
        let output = Pipe()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = [Bundle.main.path(forResource: "guardian", ofType: "sh")!, String(getpid()), "/usr/bin/ssh", "-NT",
            "-o", "RemoteCommand=none", "-o", "RequestTTY=no", "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=10", "-o", "ConnectionAttempts=1", "-o", "ControlMaster=no", "-o", "ControlPath=none",
            "-o", "ForwardAgent=no", "-o", "ForwardX11=no", "-o", "StrictHostKeyChecking=yes",
            "-L", configuration.forwardingArgument, configuration.sshDestination]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        child.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.recentLog = String((self.recentLog + text).suffix(6000))
            }
        }
        child.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self = self, self.generation == token else { return }
                self.pipe?.fileHandleForReading.readabilityHandler = nil
                self.pipe = nil
                self.process = nil
                self.request?.cancel()
                self.request = nil
                if self.wanted && !self.quitting {
                    self.setState("连接已断开", symbol: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90", detail: "SSH 退出 \(p.terminationStatus)，准备重连")
                    self.scheduleRetry()
                }
            }
        }
        process = child
        pipe = output
        do {
            try child.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard self?.generation == token else { return }
                self?.checkHealth()
            }
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            process = nil
            pipe = nil
            recentLog += "\n\(error.localizedDescription)"
            setState("启动失败", symbol: "exclamationmark.triangle", detail: "将自动重试")
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard wanted, !quitting, retry == nil else { return }
        attempts = min(attempts + 1, 5)
        let delay = min(pow(2.0, Double(attempts - 1)), 15)
        detailItem.title += " · \(Int(delay)) 秒后重试"
        let job = DispatchWorkItem { [weak self] in
            self?.retry = nil
            self?.connect()
        }
        retry = job
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: job)
    }

    private func checkHealth() {
        guard wanted, !quitting, let p = process, p.isRunning, request == nil else { return }
        let token = generation
        var req = URLRequest(url: URL(string: endpoint + "/models")!)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        request = session.dataTask(with: req) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self = self, self.generation == token, self.wanted, !self.quitting else { return }
                self.request = nil
                if let http = response as? HTTPURLResponse, error == nil {
                    self.failures = 0
                    self.attempts = 0
                    if [200, 401, 403].contains(http.statusCode) {
                        self.setState("已连接", symbol: "network", detail: "接口可达 · HTTP \(http.statusCode)")
                    } else {
                        self.setState("隧道已连接，上游异常", symbol: "exclamationmark.triangle", detail: "模型接口 HTTP \(http.statusCode)")
                    }
                } else {
                    self.failures += 1
                    self.setState("正在检查连接", symbol: "arrow.triangle.2.circlepath", detail: "接口暂时不可达")
                    if self.failures >= 2 {
                        self.stopProcess()
                        self.setState("正在重新连接", symbol: "arrow.triangle.2.circlepath", detail: "连接检查失败，自动恢复中")
                        self.scheduleRetry()
                    }
                }
            }
        }
        request?.resume()
    }

    private func stopProcess() {
        generation += 1
        request?.cancel()
        request = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        if let child = process, child.isRunning {
            child.terminate()
            // The guardian traps TERM and closes its SSH child before exiting.
            let deadline = Date().addingTimeInterval(2)
            while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        }
        process = nil
        pipe = nil
    }

    @objc private func toggle() {
        wanted.toggle()
        retry?.cancel()
        retry = nil
        if wanted { attempts = 0; connect() }
        else { stopProcess(); setState("已断开", symbol: "pause.circle", detail: "点击连接以启用本机 API 地址") }
    }

    @objc private func reconnect() {
        wanted = true
        retry?.cancel()
        retry = nil
        attempts = 0
        stopProcess()
        connect()
    }

    @objc private func woke() {
        guard wanted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard self?.wanted == true else { return }
            self?.reconnect()
        }
    }

    @objc private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(endpoint, forType: .string)
    }

    @objc private func showDetails() {
        let alert = NSAlert()
        alert.messageText = "FreeAPI · \(currentState)"
        alert.informativeText = "本机 API：\(endpoint)\nSSH：\(configuration.sshDestination)\n上游：\(configuration.remoteHost):\(configuration.remotePort)\n\nHTTP 401 表示接口可达；请在客户端填入 API Key。\n程序只转发连接，不保存 Key。断线后自动重试，退出后关闭隧道。\n不注册开机启动，不安装后台服务。\n\n最近连接日志：\n\(recentLog.isEmpty ? "暂无错误" : String(recentLog.suffix(1800)))"
        alert.addButton(withTitle: "关闭")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitting = true
        wanted = false
        retry?.cancel()
        timer?.invalidate()
        monitor.cancel()
        stopProcess()
        return .terminateNow
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
do {
    let configuration = try TunnelConfiguration.load()
    let delegate = TunnelApp(configuration: configuration)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
} catch {
    let alert = NSAlert()
    alert.messageText = "FreeAPI 配置尚未就绪"
    alert.informativeText = "请按照 README 创建或修正以下文件，然后重新打开 FreeAPI：\n\(TunnelConfiguration.fileURL.path)\n\n\(error.localizedDescription)"
    alert.addButton(withTitle: "打开配置目录")
    alert.addButton(withTitle: "退出")
    app.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn {
        let directory = TunnelConfiguration.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
