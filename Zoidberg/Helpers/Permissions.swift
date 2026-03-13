// Zoidberg/Helpers/Permissions.swift
import Cocoa
import Speech

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

    static func checkSpeechRecognition() -> PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    static func requestSpeechRecognition() async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized: continuation.resume(returning: .granted)
                default: continuation.resume(returning: .denied)
                }
            }
        }
    }

    static func openSystemSettings(for pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
