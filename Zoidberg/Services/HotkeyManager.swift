// Zoidberg/Services/HotkeyManager.swift
import HotKey
import Carbon

final class HotkeyManager {
    private var togglePanelHotKey: HotKey?
    private var dictateHotKey: HotKey?

    var onTogglePanel: (() -> Void)?
    var onToggleDictation: (() -> Void)?

    func register() {
        togglePanelHotKey = HotKey(key: .space, modifiers: .control)
        togglePanelHotKey?.keyDownHandler = { [weak self] in
            self?.onTogglePanel?()
        }

        dictateHotKey = HotKey(key: .space, modifiers: [.control, .shift])
        dictateHotKey?.keyDownHandler = { [weak self] in
            self?.onToggleDictation?()
        }
    }

    func unregister() {
        togglePanelHotKey = nil
        dictateHotKey = nil
    }
}
