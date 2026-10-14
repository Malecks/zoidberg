import Foundation
import ServiceManagement
import os

protocol LoginItemService {
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

enum LoginItem {
    private static let log = Logger(subsystem: "com.malecks.zoidberg", category: "login-item")

    @discardableResult
    static func set(_ enabled: Bool, service: LoginItemService = SMAppService.mainApp) -> Bool {
        do {
            if enabled { try service.register() } else { try service.unregister() }
            return true
        } catch {
            log.error("launch at login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            return false
        }
    }
}

enum BragMenu {
    static func updateTitle(isUpdating: Bool) -> String {
        isUpdating ? "Brag: Updating…" : "Brag: Update now"
    }
}
