import SwiftUI
import UserNotifications

@main
struct ZoidbergApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window is managed manually via AppDelegate
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var panel: KeyablePanel!
    private var settingsWindow: NSWindow?
    let appState = AppState()
    private let hotkeyManager = HotkeyManager()
    private let escapeMonitor = EscapeKeyMonitor()
    private let bragPoster = SystemNotificationPoster()
    private lazy var brag = BragController(
        runner: ProcessCommandRunner(),
        notifications: bragPoster,
        fallbackAlert: { days in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Brag review"
            alert.informativeText = days == 1 ? "1 day captured since your last review" : "\(days) days captured since your last review"
            alert.addButton(withTitle: "Review now")
            alert.addButton(withTitle: "Later")
            alert.addButton(withTitle: "Skip")
            switch alert.runModal() {
            case .alertFirstButtonReturn: return .reviewNow
            case .alertSecondButtonReturn: return .later
            default: return .skip
            }
        },
        showMessage: { title, body in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = body
            alert.runModal()
        },
        openURL: { NSWorkspace.shared.open($0) },
        scheduleLater: { seconds, work in DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work) })

    private var isPanelVisible: Bool { panel?.isVisible ?? false }
    /// App that was frontmost before the panel opened; focus goes back to it on hide.
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        bragPoster.registerCategories()
        if AppSettings.launchAtLogin { LoginItem.set(true) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Zoidberg")
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hostingController = NSHostingController(
            rootView: CapturePanel(appState: appState)
        )

        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
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

        appState.onDismiss = { [weak self] in
            self?.hidePanel()
        }

        if Permissions.checkAccessibility() == .denied {
            Permissions.requestAccessibility()
        }

        hotkeyManager.onTogglePanel = { [weak self] in
            self?.togglePanel()
        }
        hotkeyManager.register()

        escapeMonitor.onTap = { [weak self] in
            self?.hidePanel()
        }
        escapeMonitor.onHold = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.appState.isDiscardHolding = false
                self.appState.discardSession()
            }
        }
        escapeMonitor.onHoldStart = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self = self, self.escapeMonitor.isHolding else { return }
                self.appState.isDiscardHolding = true
            }
        }
        escapeMonitor.onHoldCancel = { [weak self] in
            Task { @MainActor in
                self?.appState.isDiscardHolding = false
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

        // Become the active app so Wispr Flow dictates into our text field, not the app behind
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            previousApp = front
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        appState.openCount += 1
        appState.resetIdle()

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
            guard let self = self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            if NSApp.isActive { self.previousApp?.activate() }
            self.previousApp = nil
        })
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let update = NSMenuItem(title: BragMenu.updateTitle(isUpdating: brag.isUpdating),
                                action: brag.isUpdating ? nil : #selector(bragUpdateNow), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        let review = NSMenuItem(title: "Brag: Review…", action: #selector(bragReview), keyEquivalent: "")
        review.target = self
        menu.addItem(review)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Zoidberg", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func bragUpdateNow() { Task { await brag.updateNow() } }
    @objc private func bragReview() { Task { await brag.reviewNow() } }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let route = BragURLRouter.route(url) else { continue }
            Task { await brag.handle(route) }
        }
    }

    @objc private func openSettings() {
        if let settingsWindow = settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentViewController: NSHostingController(rootView: SettingsView())
        )
        window.title = "Zoidberg Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 300))
        window.center()
        window.delegate = self
        settingsWindow = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow = nil
            // Hide dock icon again
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

/// NSPanel subclass that accepts key status without a title bar.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // SwiftUI replaces NSApp.mainMenu with a default that has no Edit menu, so editing
    // shortcuts (and Wispr Flow's synthetic ⌘V) would never reach the text view
    private static let editActions: [String: Selector] = [
        "x": #selector(NSText.cut(_:)),
        "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:)),
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
           let action = Self.editActions[event.charactersIgnoringModifiers ?? ""],
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            await self.brag.didReceive(action: action, category: category, userInfo: info)
            completionHandler()
        }
    }
}
