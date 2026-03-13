import SwiftUI

@main
struct ZoidbergApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let appState = AppState()
    private let hotkeyManager = HotkeyManager()
    private let transcriptionService = MacOSDictationService()
    private let escapeMonitor = EscapeKeyMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Use a robot-like SF Symbol. Replace with custom asset for final build.
            button.image = NSImage(systemSymbolName: "desktopcomputer.and.arrow.down", accessibilityDescription: "Zoidberg")
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: CapturePanel(appState: appState, onToggleDictation: { [weak self] in
                self?.toggleDictation()
            })
        )

        transcriptionService.delegate = self

        if Permissions.checkAccessibility() == .denied {
            Permissions.requestAccessibility()
        }

        hotkeyManager.onTogglePanel = { [weak self] in
            self?.togglePopover()
        }
        hotkeyManager.onToggleDictation = { [weak self] in
            self?.toggleDictation()
        }
        hotkeyManager.register()

        escapeMonitor.onTap = { [weak self] in
            self?.popover.performClose(nil)
        }
        escapeMonitor.onHold = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.appState.discardSession()
            }
        }
        escapeMonitor.start()
    }

    @objc private func togglePopover() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func toggleDictation() {
        if !popover.isShown {
            togglePopover()
        }

        if transcriptionService.isListening {
            transcriptionService.stopListening()
            Task { @MainActor in
                appState.stopDictation()
            }
        } else {
            Task { @MainActor in
                if Permissions.checkSpeechRecognition() == .notDetermined {
                    let _ = await Permissions.requestSpeechRecognition()
                }
                guard Permissions.checkSpeechRecognition() == .granted else {
                    Permissions.openSystemSettings(for: "Privacy_SpeechRecognition")
                    return
                }
                do {
                    try transcriptionService.startListening()
                    appState.startDictation()
                } catch {
                    print("Dictation error: \(error)")
                    appState.stopDictation()
                }
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Zoidberg", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: TranscriptionDelegate {
    func transcriptionDidUpdate(text: String) {
        Task { @MainActor in
            appState.updateTranscription(text)
        }
    }

    func transcriptionDidFinish(finalText: String) {
        Task { @MainActor in
            appState.updateTranscription(finalText)
            appState.stopDictation()
        }
    }

    func transcriptionDidFail(error: Error) {
        print("Transcription failed: \(error)")
        Task { @MainActor in
            appState.stopDictation()
        }
    }
}
