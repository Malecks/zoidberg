// Zoidberg/Services/HotkeyManager.swift
import HotKey
import Carbon

final class HotkeyManager {
    private var togglePanelHotKey: HotKey?

    var onTogglePanel: (() -> Void)?

    func register() {
        togglePanelHotKey = HotKey(key: .space, modifiers: .control)
        togglePanelHotKey?.keyDownHandler = { [weak self] in
            self?.onTogglePanel?()
        }
    }

    func unregister() {
        togglePanelHotKey = nil
    }
}
