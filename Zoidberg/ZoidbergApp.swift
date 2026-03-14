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
    private var panel: KeyablePanel!
    private let appState = AppState()
    private let hotkeyManager = HotkeyManager()
    private let transcriptionService = MacOSDictationService()
    private let escapeMonitor = EscapeKeyMonitor()

    private var isPanelVisible: Bool { panel?.isVisible ?? false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "desktopcomputer.and.arrow.down", accessibilityDescription: "Zoidberg")
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hostingController = NSHostingController(
            rootView: CapturePanel(appState: appState, onToggleDictation: { [weak self] in
                self?.toggleDictation()
            })
        )

        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
            styleMask: [.nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = NSColor(red: 0.06, green: 0.04, blue: 0.1, alpha: 1)
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.minSize = NSSize(width: 280, height: 100)
        panel.maxSize = NSSize(width: 600, height: 800)
        panel.contentViewController = hostingController
        panel.setFrameAutosaveName("ZoidbergPanel")

        // Round the entire window frame
        if let frameView = panel.contentView?.superview {
            frameView.wantsLayer = true
            frameView.layer?.cornerRadius = 40
            frameView.layer?.cornerCurve = .continuous
            frameView.layer?.masksToBounds = true
        }

        transcriptionService.delegate = self
        appState.onDismiss = { [weak self] in
            self?.hidePanel()
        }

        if Permissions.checkAccessibility() == .denied {
            Permissions.requestAccessibility()
        }

        hotkeyManager.onTogglePanel = { [weak self] in
            self?.togglePanel()
        }
        hotkeyManager.onToggleDictation = { [weak self] in
            self?.toggleDictation()
        }
        hotkeyManager.register()

        escapeMonitor.onTap = { [weak self] in
            self?.hidePanel()
        }
        escapeMonitor.onHold = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.appState.discardSession()
            }
        }
        escapeMonitor.start()
    }

    @objc private func togglePanel() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if isPanelVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        if !panel.setFrameUsingName("ZoidbergPanel") {
            guard let button = statusItem.button,
                  let buttonWindow = button.window else { return }
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(buttonRect)
            let panelWidth: CGFloat = 340
            let panelX = screenRect.midX - panelWidth / 2
            let panelY = screenRect.minY - 4
            panel.setFrameTopLeftPoint(NSPoint(x: panelX, y: panelY))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        appState.openCount += 1

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.panel.alphaValue = 1
        })
    }

    private func toggleDictation() {
        if !isPanelVisible {
            showPanel()
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

/// NSPanel subclass that accepts key status without a title bar.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
