import Foundation
import Darwin

enum TunnelError: LocalizedError {
    case portInUse(Int)
    case guardianMissing
    case failedToStart(String)

    var errorDescription: String? {
        switch self {
        case .portInUse(let port): return "本地端口 \(port) 已被占用"
        case .guardianMissing: return "找不到 guardian.sh，应用包不完整"
        case .failedToStart(let message): return "SSH 启动失败：\(message)"
        }
    }
}

final class TunnelController {
    private(set) var backend: Backend
    let ownerPID: pid_t
    let guardianPath: String

    private var process: Process?
    private var pipe: Pipe?
    private var generation = 0
    private let stopLock = NSLock()
    private var stopNotified = false

    var onLog: ((String) -> Void)?
    var onExit: ((Int32) -> Void)?
    var isRunning: Bool { process?.isRunning == true }

    init(backend: Backend, ownerPID: pid_t, guardianPath: String) {
        self.backend = backend
        self.ownerPID = ownerPID
        self.guardianPath = guardianPath
    }

    func start() throws {
        guard backend.transport == .ssh, let localPort = backend.localPort else {
            throw TunnelError.failedToStart("SSH 后端缺少本地端口")
        }
        guard !backend.sshTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TunnelError.failedToStart("SSH 目标为空")
        }
        guard PortChecker.isAvailable(localPort) else {
            throw TunnelError.portInUse(localPort)
        }
        guard FileManager.default.isExecutableFile(atPath: guardianPath) else {
            throw TunnelError.guardianMissing
        }

        generation += 1
        let token = generation
        stopLock.lock()
        stopNotified = false
        stopLock.unlock()

        let output = Pipe()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = [
            guardianPath, String(ownerPID), "/usr/bin/ssh", "-NT",
            "-o", "RemoteCommand=none",
            "-o", "RequestTTY=no",
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=10",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=10",
            "-o", "ConnectionAttempts=1",
            "-o", "ControlMaster=no",
            "-o", "ControlPath=none",
            "-o", "ForwardAgent=no",
            "-o", "ForwardX11=no",
            "-o", "StrictHostKeyChecking=yes",
            "-L", backend.forwardingArgument,
            backend.sshTarget
        ]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        child.standardError = output

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.onLog?(text) }
        }

        child.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.pipe?.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.pipe = nil
                self.onExit?(status)
            }
        }

        do {
            try child.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw TunnelError.failedToStart(error.localizedDescription)
        }
        process = child
        pipe = output
    }

    func stop(completion: (() -> Void)? = nil) {
        generation += 1
        pipe?.fileHandleForReading.readabilityHandler = nil
        guard let child = process else {
            notifyStopped(completion)
            return
        }

        child.terminationHandler = { [weak self] _ in
            self?.notifyStopped(completion)
        }
        child.terminate()

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if child.isRunning {
                kill(child.processIdentifier, SIGKILL)
            }
            self?.notifyStopped(completion)
        }
    }

    private func notifyStopped(_ completion: (() -> Void)?) {
        stopLock.lock()
        if stopNotified {
            stopLock.unlock()
            return
        }
        stopNotified = true
        stopLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.process = nil
            self?.pipe = nil
            completion?()
        }
    }
}
