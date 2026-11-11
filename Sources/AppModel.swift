import Foundation
import AppKit
import Network
import Combine

final class AppModel: ObservableObject {
    @Published private(set) var configuration: AppConfiguration
    @Published var selectedID: UUID?
    @Published private(set) var selectedIDs: Set<UUID> = []
    private var selectionAnchorID: UUID?
    @Published var searchText: String = ""
    @Published private(set) var runtimes: [UUID: BackendRuntime] = [:]
    @Published private(set) var apiKeys: [UUID: String] = [:]
    @Published private(set) var testingIDs: Set<UUID> = []
    @Published private(set) var toast: String?
    @Published private(set) var startupError: String?
    @Published private(set) var isShuttingDown = false
    @Published private(set) var didMigrate = false
    @Published private(set) var configLocationWarning: String?
    @Published private(set) var backups: [ConfigBackup] = []

    var onOpenWindow: ((UUID?) -> Void)?

    private var tunnels: [UUID: TunnelController] = [:]
    private var retryTasks: [UUID: DispatchWorkItem] = [:]
    private var retryAttempts: [UUID: Int] = [:]
    private var editTasks: [UUID: DispatchWorkItem] = [:]
    private var saveTask: DispatchWorkItem?
    private var keySaveTasks: [UUID: DispatchWorkItem] = [:]
    private var checks: [UUID: URLSessionDataTask] = [:]
    private var checkTokens: [UUID: UUID] = [:]
    private var toastTask: DispatchWorkItem?
    private var healthTimer: Timer?
    private let monitor = NWPathMonitor()
    private let session: URLSession
    private var started = false
    private var wakeObserver: NSObjectProtocol?
    private var lastPathSatisfied: Bool?
    private var configWatchTimer: Timer?
    private var lastKnownConfigData: Data?
    private var isApplyingRemoteConfig = false

    init() {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 5
        sessionConfiguration.timeoutIntervalForResource = 6
        sessionConfiguration.connectionProxyDictionary = [
            "HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0, "ProxyAutoConfigEnable": 0
        ]
        session = URLSession(configuration: sessionConfiguration)

        do {
            let loaded = try ConfigurationStore.load()
            configuration = loaded.configuration.sanitized()
            startupError = nil
            didMigrate = loaded.migrated
            if loaded.migrated { _ = try? ConfigurationStore.save(configuration) }
        } catch let error as ConfigurationStoreError {
            configuration = AppConfiguration()
            if case .missing = error {
                startupError = nil
            } else {
                startupError = error.localizedDescription
            }
        } catch {
            configuration = AppConfiguration()
            startupError = error.localizedDescription
        }

        selectedID = configuration.backends.first?.id
        if let selectedID {
            selectedIDs = [selectedID]
            selectionAnchorID = selectedID
        }
        for backend in configuration.backends {
            if let key = KeychainStore.read(account: backend.id.uuidString) {
                apiKeys[backend.id] = key
            }
            runtimes[backend.id] = BackendRuntime()
        }
        lastKnownConfigData = ConfigurationStore.currentData()
        configLocationWarning = ConfigLocation.fallbackWarning
        backups = ConfigBackupStore.load()
        if backups.isEmpty, !configuration.backends.isEmpty {
            backups = ConfigBackupStore.add(configuration: configuration, summary: "初始配置")
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        startNetworkMonitor()
        startHealthTimer()
        startConfigWatcher()
        observeWake()
        for backend in configuration.backends where backend.enabled {
            startBackend(backend.id)
        }
        if let warning = configLocationWarning {
            showToast(warning)
        }
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        healthTimer?.invalidate()
        healthTimer = nil
        configWatchTimer?.invalidate()
        configWatchTimer = nil
        monitor.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        saveTask?.cancel()
        saveNow()
        flushKeys()
        for work in retryTasks.values { work.cancel() }
        for work in editTasks.values { work.cancel() }
        for task in checks.values { task.cancel() }
        for tunnel in tunnels.values { tunnel.stop() }
        tunnels.removeAll()
    }

    private func startHealthTimer() {
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.checkEnabledBackends()
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                let satisfied = path.status == .satisfied
                let previous = self.lastPathSatisfied
                self.lastPathSatisfied = satisfied
                if previous == false && satisfied {
                    self.scheduleRecovery(after: 1)
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "freeapi.network"))
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleRecovery(after: 2)
        }
    }

    private func scheduleRecovery(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isShuttingDown else { return }
            for backend in self.configuration.backends where backend.enabled {
                self.restartBackend(backend.id)
            }
        }
    }

    // MARK: - Reading state

    var backends: [Backend] { configuration.backends }
    var mode: RunMode { configuration.mode }
    var enabledCount: Int { configuration.backends.filter(\.enabled).count }
    var connectedCount: Int {
        configuration.backends.filter { $0.enabled && state(for: $0) == .connected }.count
    }

    var filteredBackends: [Backend] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return configuration.backends }
        return configuration.backends.filter {
            ($0.name + " " + $0.host).lowercased().contains(query)
        }
    }

    var overallState: ConnectionState {
        let enabled = configuration.backends.filter(\.enabled)
        guard !enabled.isEmpty else { return .off }
        let states = enabled.map { state(for: $0) }
        if states.contains(.error) { return .error }
        if states.allSatisfy({ $0 == .connected }) { return .connected }
        if states.contains(.degraded) { return .degraded }
        if states.contains(.connecting) { return .connecting }
        return .off
    }

    func backend(id: UUID) -> Backend? { configuration.backend(id: id) }

    func runtime(for id: UUID) -> BackendRuntime { runtimes[id] ?? BackendRuntime() }

    func state(for backend: Backend) -> ConnectionState {
        guard backend.enabled else { return .off }
        let current = runtimes[backend.id]?.state ?? .off
        return current == .off ? .connecting : current
    }

    func latencyText(for backend: Backend) -> String {
        guard backend.enabled else { return "—" }
        switch state(for: backend) {
        case .connecting: return "连接中"
        case .error: return "失败"
        default:
            if let latency = runtimes[backend.id]?.latency { return "\(latency) ms" }
            return "—"
        }
    }

    func httpText(for backend: Backend) -> String {
        guard let status = runtimes[backend.id]?.httpStatus else { return "—" }
        return "HTTP \(status)"
    }

    func lastCheckedText(for backend: Backend) -> String {
        relativeTime(runtimes[backend.id]?.lastChecked)
    }

    func errorText(for backend: Backend) -> String? {
        runtimes[backend.id]?.errorMessage
    }

    func log(for backend: Backend) -> String {
        runtimes[backend.id]?.log ?? ""
    }

    func relativeTime(_ date: Date?) -> String {
        guard let date else { return "未检查" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 5 { return "刚刚" }
        if seconds < 60 { return "\(seconds) 秒前" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        return "\(hours) 小时前"
    }

    func sshCommand(for backend: Backend) -> String { backend.sshCommand }

    func apiKey(for id: UUID) -> String { apiKeys[id] ?? "" }

    func isTesting(_ id: UUID) -> Bool { testingIDs.contains(id) }

    // MARK: - Selection and editing

    func select(_ id: UUID, extending: Bool = false, within order: [UUID]? = nil) {
        guard configuration.index(id: id) != nil else { return }
        let ids = order ?? configuration.backends.map(\.id)
        guard let targetIndex = ids.firstIndex(of: id) else { return }
        if extending,
           let anchor = selectionAnchorID,
           let anchorIndex = ids.firstIndex(of: anchor) {
            let low = min(anchorIndex, targetIndex)
            let high = max(anchorIndex, targetIndex)
            selectedIDs = Set(ids[low...high])
        } else {
            selectedIDs = [id]
            selectionAnchorID = id
        }
        selectedID = id
    }

    var selectedBackends: [Backend] {
        configuration.backends.filter { selectedIDs.contains($0.id) }
    }

    func openMainWindow(select id: UUID? = nil) {
        if let id { select(id) }
        onOpenWindow?(id)
    }

    func updateBackend(id: UUID, _ mutate: (inout Backend) -> Void) {
        guard let index = configuration.index(id: id) else { return }
        let previous = configuration.backends[index]
        var backend = previous
        mutate(&backend)
        configuration.backends[index] = backend
        scheduleSave()
        guard backend.enabled else { return }

        let tunnelChanged = previous.transport != backend.transport
            || previous.host != backend.host
            || previous.port != backend.port
            || previous.localPort != backend.localPort
            || previous.sshTarget != backend.sshTarget
        if tunnelChanged {
            scheduleRestart(id)
        } else if previous.scheme != backend.scheme || previous.apiPath != backend.apiPath {
            scheduleCheck(id)
        }
    }

    func setAPIKey(_ value: String, for id: UUID) {
        apiKeys[id] = value
        keySaveTasks[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            KeychainStore.write(self.apiKeys[id] ?? "", account: id.uuidString)
        }
        keySaveTasks[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: - Commands

    func setMode(_ mode: RunMode) {
        guard mode != configuration.mode else { return }
        configuration.mode = mode
        if mode == .single {
            let keep = selectedID
                ?? configuration.backends.first(where: { $0.enabled })?.id
                ?? configuration.backends.first?.id
            for backend in configuration.backends where backend.id != keep {
                if backend.enabled { stopBackend(backend.id) }
                if let index = configuration.index(id: backend.id) {
                    configuration.backends[index].enabled = false
                }
            }
            if let keep, let index = configuration.index(id: keep) {
                configuration.backends[index].enabled = true
                selectedID = keep
                selectedIDs = [keep]
                selectionAnchorID = keep
                startBackend(keep)
            }
        } else {
            for backend in configuration.backends where backend.enabled {
                startBackend(backend.id)
            }
        }
        scheduleSave()
        showToast(mode == .single ? "单路模式：只运行当前选中的后端" : "并行模式：每个后端使用独立本地端口")
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = configuration.index(id: id) else { return }
        if enabled {
            do {
                var backend = try configuration.backends[index].validated()
                backend.enabled = true
                if configuration.mode == .single {
                    for other in configuration.backends where other.id != id && other.enabled {
                        stopBackend(other.id)
                        if let otherIndex = configuration.index(id: other.id) {
                            configuration.backends[otherIndex].enabled = false
                        }
                    }
                    selectedID = id
                    selectedIDs = [id]
                    selectionAnchorID = id
                }
                configuration.backends[index] = backend
                scheduleSave()
                startBackend(id)
            } catch {
                mutateRuntime(id) { runtime in
                    runtime.state = .error
                    runtime.errorMessage = error.localizedDescription
                }
                showToast(error.localizedDescription)
            }
        } else {
            configuration.backends[index].enabled = false
            stopBackend(id)
            scheduleSave()
        }
    }

    func setTransport(_ transport: BackendTransport, for id: UUID) {
        let used = Set(configuration.backends.filter { $0.id != id }.compactMap(\.localPort))
        updateBackend(id: id) { backend in
            backend.transport = transport
            if transport == .ssh && backend.localPort == nil {
                backend.localPort = PortChecker.nextAvailable(startingAt: 18189, excluding: used)
            }
        }
    }

    func setAllEnabled(_ enabled: Bool) {
        if enabled {
            if configuration.mode == .single {
                if let keep = selectedID ?? configuration.backends.first?.id {
                    setEnabled(true, for: keep)
                }
            } else {
                for backend in configuration.backends where !backend.enabled {
                    setEnabled(true, for: backend.id)
                }
            }
        } else {
            for backend in configuration.backends where backend.enabled {
                setEnabled(false, for: backend.id)
            }
        }
    }

    func addBackend(transport: BackendTransport = .ssh) {
        let used = Set(configuration.backends.compactMap(\.localPort))
        let name = "新后端 \(configuration.backends.count + 1)"
        let backend: Backend
        switch transport {
        case .ssh:
            backend = Backend(
                name: name,
                transport: .ssh,
                scheme: "http",
                host: "",
                port: 8080,
                apiPath: "/v1",
                localPort: PortChecker.nextAvailable(startingAt: 18189, excluding: used),
                sshTarget: "",
                enabled: false
            )
        case .direct:
            backend = Backend(
                name: name,
                transport: .direct,
                scheme: "https",
                host: "",
                port: 443,
                apiPath: "/v1",
                localPort: nil,
                sshTarget: "",
                enabled: false
            )
        }
        configuration.backends.append(backend)
        selectedID = backend.id
        selectedIDs = [backend.id]
        selectionAnchorID = backend.id
        runtimes[backend.id] = BackendRuntime()
        scheduleSave()
        showToast(transport == .ssh ? "已添加 SSH 后端，填写地址后启用" : "已添加直连后端，填写地址后启用")
    }

    @discardableResult
    func addService(address: String, key: String) throws -> Backend {
        guard let parsed = ServiceAddress.parse(address) else {
            throw BackendError.invalid("请填写完整的 API 地址")
        }
        let candidate = Backend(
            name: parsed.host,
            transport: .direct,
            scheme: parsed.scheme,
            host: parsed.host,
            port: parsed.port,
            apiPath: parsed.path,
            localPort: nil,
            sshTarget: "",
            enabled: true
        )
        let backend = try candidate.validated()
        configuration.backends.append(backend)
        selectedID = backend.id
        selectedIDs = [backend.id]
        selectionAnchorID = backend.id
        runtimes[backend.id] = BackendRuntime()
        if configuration.mode == .single {
            for other in configuration.backends where other.id != backend.id && other.enabled {
                setEnabled(false, for: other.id)
            }
        }
        if !key.isEmpty {
            setAPIKey(key, for: backend.id)
        }
        scheduleSave()
        startBackend(backend.id)
        showToast("已添加并测试「\(backend.name)」")
        return backend
    }

    func deleteSelected() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        let firstIndex = configuration.backends.firstIndex { ids.contains($0.id) } ?? 0
        let removed = configuration.backends.filter { ids.contains($0.id) }.count
        for id in ids {
            if configuration.backend(id: id)?.enabled == true { stopBackend(id) }
            keySaveTasks[id]?.cancel()
            keySaveTasks[id] = nil
            KeychainStore.delete(account: id.uuidString)
            apiKeys.removeValue(forKey: id)
            runtimes.removeValue(forKey: id)
        }
        configuration.backends.removeAll { ids.contains($0.id) }
        let next: Backend?
        if configuration.backends.isEmpty {
            next = nil
        } else if firstIndex < configuration.backends.count {
            next = configuration.backends[firstIndex]
        } else {
            next = configuration.backends.last
        }
        selectedID = next?.id
        selectedIDs = next.map { Set([$0.id]) } ?? []
        selectionAnchorID = next?.id
        scheduleSave()
        showToast(removed == 1 ? "已删除 1 个服务" : "已删除 \(removed) 个服务")
    }

    func toggleSelectedEnabled() {
        let selected = selectedBackends
        guard !selected.isEmpty else { return }
        let allOn = selected.allSatisfy(\.enabled)
        if !allOn && configuration.mode == .single {
            if let primary = selectedID ?? selected.first?.id {
                setEnabled(true, for: primary)
            }
            showToast("单路模式只启用当前服务")
            return
        }
        for backend in selected {
            setEnabled(!allOn, for: backend.id)
        }
        showToast(allOn ? "已禁用 \(selected.count) 个服务" : "已启用 \(selected.count) 个服务")
    }

    func deleteBackend(_ id: UUID) {
        if configuration.backend(id: id)?.enabled == true { stopBackend(id) }
        configuration.backends.removeAll { $0.id == id }
        runtimes.removeValue(forKey: id)
        apiKeys.removeValue(forKey: id)
        KeychainStore.delete(account: id.uuidString)
        selectedIDs.remove(id)
        if selectedID == id {
            if let next = configuration.backends.first {
                selectedID = next.id
                selectedIDs = [next.id]
                selectionAnchorID = next.id
            } else {
                selectedID = nil
                selectedIDs = []
                selectionAnchorID = nil
            }
        }
        scheduleSave()
        showToast("已删除后端")
    }

    func testConnection(_ id: UUID) {
        guard let backend = configuration.backend(id: id) else { return }
        do {
            _ = try backend.validated()
        } catch {
            showToast(error.localizedDescription)
            return
        }
        testingIDs.insert(id)
        check(backend, manual: true)
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    // MARK: - Configuration location

    var configLocationLabel: String { ConfigLocation.displayName }
    var isUsingICloudConfig: Bool { ConfigLocation.isUsingICloud }
    var isUsingLocalConfig: Bool { ConfigLocation.isUsingLocal }

    func useICloudLocation() {
        switchConfigLocation(loadExisting: true) { try ConfigLocation.useICloud() }
    }

    func useLocalLocation() {
        switchConfigLocation(loadExisting: false) { ConfigLocation.useLocal() }
    }

    func chooseConfigFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "使用此文件夹"
        panel.message = "选择保存 FreeAPI 配置的文件夹。选择 iCloud Drive 中的文件夹可多端同步。"
        panel.directoryURL = ConfigLocation.activeDirectory
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switchConfigLocation(loadExisting: true) { try ConfigLocation.setCustomFolder(url) }
    }

    func reloadConfiguration() {
        do {
            let loaded = try ConfigurationStore.load()
            applyLoadedConfiguration(loaded.configuration)
            lastKnownConfigData = ConfigurationStore.currentData()
            if loaded.migrated { saveNow() }
            showToast("已重新载入配置")
        } catch {
            showToast("重新载入失败：\(error.localizedDescription)")
        }
    }

    private func switchConfigLocation(loadExisting: Bool, _ action: () throws -> Void) {
        let snapshot = ConfigLocation.snapshot()
        do {
            try action()
        } catch {
            ConfigLocation.restore(snapshot)
            showToast(error.localizedDescription)
            return
        }

        let target = ConfigurationStore.fileURL
        if loadExisting, FileManager.default.fileExists(atPath: target.path) {
            do {
                let loaded = try ConfigurationStore.load()
                applyLoadedConfiguration(loaded.configuration)
                lastKnownConfigData = ConfigurationStore.currentData()
                if loaded.migrated { saveNow() }
                showToast("已载入 \(ConfigLocation.displayName) 的配置")
            } catch {
                ConfigLocation.restore(snapshot)
                showToast("载入失败：\(error.localizedDescription)")
            }
        } else {
            do {
                try persistNow()
                showToast("配置已保存到 \(ConfigLocation.displayName)，之后会实时同步")
            } catch {
                ConfigLocation.restore(snapshot)
                showToast("保存失败：\(error.localizedDescription)")
            }
        }
    }

    private func applyLoadedConfiguration(_ loaded: AppConfiguration) {
        isApplyingRemoteConfig = true
        defer { isApplyingRemoteConfig = false }

        for backend in configuration.backends {
            stopBackend(backend.id)
        }
        for (id, work) in editTasks {
            work.cancel()
            editTasks[id] = nil
        }
        for (id, work) in retryTasks {
            work.cancel()
            retryTasks[id] = nil
        }

        let sanitized = loaded.sanitized()
        configuration = sanitized
        selectedID = sanitized.backends.first?.id
        if let selectedID {
            selectedIDs = [selectedID]
            selectionAnchorID = selectedID
        } else {
            selectedIDs = []
            selectionAnchorID = nil
        }

        var newRuntimes: [UUID: BackendRuntime] = [:]
        var newKeys: [UUID: String] = [:]
        for backend in sanitized.backends {
            newRuntimes[backend.id] = BackendRuntime()
            if let key = KeychainStore.read(account: backend.id.uuidString) {
                newKeys[backend.id] = key
            }
        }
        runtimes = newRuntimes
        apiKeys = newKeys

        for backend in sanitized.backends where backend.enabled {
            startBackend(backend.id)
        }
    }

    private func startConfigWatcher() {
        let timer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in
            self?.pollConfigFile()
        }
        RunLoop.main.add(timer, forMode: .common)
        configWatchTimer = timer
    }

    private func pollConfigFile() {
        guard !isShuttingDown, saveTask == nil, !isApplyingRemoteConfig else { return }
        let known = lastKnownConfigData
        DispatchQueue.global(qos: .utility).async {
            guard let data = ConfigurationStore.currentData(),
                  data != known,
                  let decoded = try? ConfigurationStore.decode(data) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      !self.isShuttingDown,
                      self.saveTask == nil,
                      !self.isApplyingRemoteConfig,
                      data != self.lastKnownConfigData else { return }
                self.applyLoadedConfiguration(decoded)
                self.lastKnownConfigData = data
                self.showToast("已载入同步文件夹中的新配置")
            }
        }
    }

    private func persistNow(summaryOverride: String? = nil) throws {
        let sanitized = configuration.sanitized()
        configuration = sanitized

        let previousData = ConfigurationStore.currentData()
        let previousConfiguration = previousData.flatMap { try? ConfigurationStore.decode($0) }
        if previousConfiguration == sanitized {
            lastKnownConfigData = previousData
            return
        }

        let summary = summaryOverride ?? ConfigurationDiff.summary(from: previousConfiguration, to: sanitized)
        let data = try ConfigurationStore.save(sanitized)
        backups = ConfigBackupStore.add(configuration: sanitized, summary: summary)
        lastKnownConfigData = data
    }

    func saveNow() {
        do {
            try persistNow()
        } catch {
            showToast("保存失败：\(error.localizedDescription)")
        }
    }

    var lastBackupText: String {
        backups.first.map { backupTimeText($0.createdAt) } ?? "暂无"
    }

    func backupTimeText(_ date: Date) -> String {
        Self.backupDateFormatter.string(from: date)
    }

    func restoreBackup(_ backup: ConfigBackup) {
        do {
            try persistNow()
        } catch {
            showToast("保存当前配置失败：\(error.localizedDescription)")
            return
        }
        applyLoadedConfiguration(backup.configuration)
        do {
            try persistNow(summaryOverride: "恢复到 \(backupTimeText(backup.createdAt)) 的配置")
            showToast("已恢复到 \(backupTimeText(backup.createdAt)) 的配置")
        } catch {
            showToast("恢复保存失败：\(error.localizedDescription)")
        }
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private func flushKeys() {
        for (id, value) in apiKeys {
            keySaveTasks[id]?.cancel()
            KeychainStore.write(value, account: id.uuidString)
        }
    }

    // MARK: - Tunnel lifecycle

    private var guardianPath: String {
        if let path = Bundle.main.path(forResource: "guardian", ofType: "sh") { return path }
        return URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("guardian.sh")
            .path
    }

    private func startBackend(_ id: UUID) {
        guard !isShuttingDown, let backend = configuration.backend(id: id), backend.enabled else { return }
        let validated: Backend
        do {
            validated = try backend.validated()
        } catch {
            mutateRuntime(id) { runtime in
                runtime.state = .error
                runtime.errorMessage = error.localizedDescription
            }
            return
        }
        if let index = configuration.index(id: id), validated != configuration.backends[index] {
            configuration.backends[index] = validated
        }

        if backend.transport == .direct {
            mutateRuntime(id) { if $0.state != .connected { $0.state = .connecting } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, let current = self.configuration.backend(id: id), current.enabled else { return }
                self.check(current, manual: false)
            }
            return
        }

        if let existing = tunnels[id] {
            if existing.isRunning { return }
            tunnels[id] = nil
            existing.stop { [weak self] in self?.startBackend(id) }
            return
        }

        guard let port = ensureLocalPort(for: id),
              var latest = configuration.backend(id: id) else { return }
        latest.localPort = port
        let controller = TunnelController(
            backend: latest,
            ownerPID: ProcessInfo.processInfo.processIdentifier,
            guardianPath: guardianPath
        )
        controller.onLog = { [weak self] text in self?.appendLog(id: id, text: text) }
        controller.onExit = { [weak self, weak controller] status in
            guard let self, let controller, self.tunnels[id] === controller else { return }
            self.handleTunnelExit(id: id, status: status)
        }
        tunnels[id] = controller
        mutateRuntime(id) { runtime in
            runtime.state = .connecting
            runtime.errorMessage = nil
            runtime.consecutiveFailures = 0
        }
        do {
            try controller.start()
            cancelRetry(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let current = self.configuration.backend(id: id), current.enabled else { return }
                self.check(current, manual: false)
            }
        } catch {
            tunnels[id] = nil
            mutateRuntime(id) { runtime in
                runtime.state = .error
                runtime.errorMessage = error.localizedDescription
            }
            scheduleRetry(id)
        }
    }

    private func restartBackend(_ id: UUID) {
        guard !isShuttingDown, let backend = configuration.backend(id: id), backend.enabled else { return }
        cancelRetry(id)
        mutateRuntime(id) { runtime in
            runtime.state = .connecting
            runtime.consecutiveFailures = 0
            runtime.errorMessage = nil
        }
        if backend.transport == .direct {
            check(backend, manual: false)
            return
        }
        if let tunnel = tunnels[id] {
            tunnels[id] = nil
            tunnel.stop { [weak self] in self?.startBackend(id) }
        } else {
            startBackend(id)
        }
    }

    private func stopBackend(_ id: UUID) {
        cancelRetry(id)
        checkTokens[id] = nil
        checks[id]?.cancel()
        checks[id] = nil
        if let tunnel = tunnels[id] {
            tunnels[id] = nil
            tunnel.stop()
        }
        mutateRuntime(id) { runtime in
            runtime.state = .off
            runtime.errorMessage = nil
            runtime.consecutiveFailures = 0
        }
    }

    private func handleTunnelExit(id: UUID, status: Int32) {
        guard !isShuttingDown,
              let backend = configuration.backend(id: id),
              backend.enabled else { return }
        tunnels[id] = nil
        mutateRuntime(id) { runtime in
            runtime.state = .error
            runtime.errorMessage = "SSH 退出 \(status)"
            runtime.consecutiveFailures = 0
        }
        scheduleRetry(id)
    }

    private func scheduleRetry(_ id: UUID) {
        guard !isShuttingDown,
              let backend = configuration.backend(id: id),
              backend.enabled else { return }
        cancelRetry(id)
        let attempt = min((retryAttempts[id] ?? 0) + 1, 5)
        retryAttempts[id] = attempt
        let delay = min(pow(2.0, Double(attempt - 1)), 15)
        mutateRuntime(id) { runtime in
            let base = (runtime.errorMessage ?? "连接已断开")
                .replacingOccurrences(of: #"，\d+ 秒后重试"#, with: "", options: .regularExpression)
            runtime.state = .error
            runtime.errorMessage = "\(base)，\(Int(delay)) 秒后重试"
        }
        let work = DispatchWorkItem { [weak self] in
            self?.retryTasks[id] = nil
            self?.startBackend(id)
        }
        retryTasks[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelRetry(_ id: UUID) {
        retryTasks[id]?.cancel()
        retryTasks[id] = nil
    }

    private func ensureLocalPort(for id: UUID) -> Int? {
        guard let index = configuration.index(id: id) else { return nil }
        var backend = configuration.backends[index]
        guard backend.transport == .ssh else { return backend.localPort }
        let used = Set(configuration.backends.filter { $0.id != id }.compactMap(\.localPort))
        if let port = backend.localPort, (1024...65535).contains(port),
           !used.contains(port), PortChecker.isAvailable(port) {
            return port
        }
        let port = PortChecker.nextAvailable(startingAt: 18189, excluding: used)
        backend.localPort = port
        configuration.backends[index] = backend
        scheduleSave()
        showToast("本地端口已调整为 \(port)")
        return port
    }

    private func scheduleRestart(_ id: UUID) {
        editTasks[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.editTasks[id] = nil
            self?.restartBackend(id)
        }
        editTasks[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func scheduleCheck(_ id: UUID) {
        editTasks[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.editTasks[id] = nil
            guard let self, let backend = self.configuration.backend(id: id), backend.enabled else { return }
            self.check(backend, manual: false)
        }
        editTasks[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveTask = nil
            self?.saveNow()
        }
        saveTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: - Health checks

    private func checkEnabledBackends() {
        guard !isShuttingDown else { return }
        for backend in configuration.backends where backend.enabled {
            check(backend, manual: false)
        }
    }

    private func check(_ backend: Backend, manual: Bool) {
        guard !isShuttingDown else { return }
        if !manual, checkTokens[backend.id] != nil { return }
        if manual { testingIDs.insert(backend.id) }
        checkTokens[backend.id] = nil
        checks[backend.id]?.cancel()

        guard let url = URL(string: backend.healthURL) else {
            if manual {
                testingIDs.remove(backend.id)
                showToast("地址格式不正确")
            }
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let key = apiKeys[backend.id] ?? ""
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let token = UUID()
        checkTokens[backend.id] = token
        let startedAt = Date()
        let task = session.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self, self.checkTokens[backend.id] == token else { return }
                self.checkTokens[backend.id] = nil
                self.checks[backend.id] = nil
                if manual { self.testingIDs.remove(backend.id) }
                if let urlError = error as? URLError, urlError.code == .cancelled { return }

                let current = self.configuration.backend(id: backend.id) ?? backend
                let milliseconds = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))

                if let http = response as? HTTPURLResponse, error == nil {
                    let reachable = [200, 401, 403].contains(http.statusCode)
                    self.mutateRuntime(backend.id) { runtime in
                        runtime.latency = milliseconds
                        runtime.httpStatus = http.statusCode
                        runtime.lastChecked = Date()
                        runtime.history = Array((runtime.history + [milliseconds]).suffix(20))
                        runtime.consecutiveFailures = 0
                        runtime.errorMessage = reachable ? nil : "上游 HTTP \(http.statusCode)"
                        if current.enabled {
                            runtime.state = reachable ? .connected : .degraded
                        } else {
                            runtime.state = .off
                        }
                    }
                    if current.enabled {
                        self.retryAttempts[backend.id] = 0
                    }
                    if manual {
                        self.showToast(
                            reachable
                                ? "连接正常 · HTTP \(http.statusCode) · \(milliseconds) ms"
                                : "上游返回 HTTP \(http.statusCode)"
                        )
                    }
                } else {
                    let message = error?.localizedDescription ?? "无法连接"
                    self.handleCheckFailure(id: backend.id, message: message, enabled: current.enabled, manual: manual)
                }
            }
        }
        checks[backend.id] = task
        task.resume()
    }

    private func handleCheckFailure(id: UUID, message: String, enabled: Bool, manual: Bool) {
        var shouldRestart = false
        mutateRuntime(id) { runtime in
            runtime.lastChecked = Date()
            runtime.errorMessage = message
            runtime.consecutiveFailures += 1
            if enabled {
                if runtime.consecutiveFailures >= 2 {
                    runtime.state = .error
                    shouldRestart = true
                } else {
                    runtime.state = .degraded
                }
            } else {
                runtime.state = .off
            }
        }
        if manual { showToast("测试失败：\(message)") }
        if shouldRestart,
           let backend = configuration.backend(id: id),
           backend.enabled,
           backend.transport == .ssh,
           retryTasks[id] == nil {
            restartBackend(id)
        }
    }

    private func appendLog(id: UUID, text: String) {
        mutateRuntime(id) { runtime in
            runtime.log = String((runtime.log + text).suffix(6000))
        }
    }

    private func mutateRuntime(_ id: UUID, _ body: (inout BackendRuntime) -> Void) {
        var all = runtimes
        var runtime = all[id] ?? BackendRuntime()
        body(&runtime)
        all[id] = runtime
        runtimes = all
    }
}
