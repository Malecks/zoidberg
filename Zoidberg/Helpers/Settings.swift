// Zoidberg/Helpers/Settings.swift
import Foundation

enum AppSettings {
    static var defaults: UserDefaults = .standard

    static var vaultPath: String {
        get { defaults.string(forKey: "vaultPath") ?? NSHomeDirectory() + "/Documents/Obsidian Vault" }
        set { defaults.set(newValue, forKey: "vaultPath") }
    }

    static var claudeApiKey: String? {
        get { defaults.string(forKey: "claudeApiKey") }
        set { defaults.set(newValue, forKey: "claudeApiKey") }
    }

    static var hasClaudeApiKey: Bool {
        guard let key = claudeApiKey else { return false }
        return !key.isEmpty
    }

    static var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    static var togglePanelHotkey: String {
        get { defaults.string(forKey: "togglePanelHotkey") ?? "ctrl+space" }
        set { defaults.set(newValue, forKey: "togglePanelHotkey") }
    }

    static var dictateHotkey: String {
        get { defaults.string(forKey: "dictateHotkey") ?? "ctrl+shift+space" }
        set { defaults.set(newValue, forKey: "dictateHotkey") }
    }

    static var autoCloseEnabled: Bool {
        get { defaults.object(forKey: "autoCloseEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoCloseEnabled") }
    }

    static var autoCloseSeconds: Double {
        get {
            let val = defaults.double(forKey: "autoCloseSeconds")
            return val > 0 ? val : 10
        }
        set { defaults.set(newValue, forKey: "autoCloseSeconds") }
    }

    static var bragPath: String {
        get { defaults.string(forKey: "bragPath") ?? NSHomeDirectory() + "/.local/bin/brag" }
        set { defaults.set(newValue, forKey: "bragPath") }
    }

    static var bragLaterSeconds: Double {
        get { (defaults.object(forKey: "bragLaterSeconds") as? Double) ?? 3600 }
        set { defaults.set(newValue, forKey: "bragLaterSeconds") }
    }
}
