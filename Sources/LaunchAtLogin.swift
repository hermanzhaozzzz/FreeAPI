import Foundation
import ServiceManagement

enum LaunchAtLogin {
    enum State {
        case off
        case on
        case awaitingApproval
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .awaitingApproval
        default: return .off
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status == .notRegistered || service.status == .notFound else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered, service.status != .notFound else { return }
            try service.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
