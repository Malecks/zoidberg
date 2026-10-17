// Zoidberg/Helpers/Permissions.swift
import Cocoa

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

enum Permissions {
    static func checkAccessibility() -> PermissionStatus {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        )
        return trusted ? .granted : .denied
    }

    static func requestAccessibility() {
        let _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
    }
}
