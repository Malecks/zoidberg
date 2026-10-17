// Zoidberg/AppState.swift
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var currentSession = CaptureSession()
    @Published var isDragOver = false
    @Published var toastMessage: String?
    @Published var toastIsError = false
    @Published var openCount = 0
    @Published var isIdle = false
    @Published var isCleaning = false
    @Published var isAutoClosing = false
    @Published var isDiscardHolding = false

    /// Called when the panel should close (after save, discard, etc.)
    var onDismiss: (() -> Void)?
    @Published var settingsRequested = false

    private var idleTimer: Timer?
    private var autoCloseTimer: Timer?
    private let idleDelay: TimeInterval = 1.5
    private let hintDuration: TimeInterval = 2.5
    private var autoCloseDelay: TimeInterval { AppSettings.autoCloseSeconds }

    private var toastTimer: Timer?

    private let persistencePath: String = {
        let dir = NSHomeDirectory() + "/Library/Application Support/Zoidberg"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/pending-session.json"
    }()

    init() {
        loadPersistedSession()
    }

    var hasContent: Bool { !currentSession.isEmpty }

    /// Call whenever the user does something — resets the idle countdown
    func resetIdle(showHint: Bool = false) {
        isIdle = false
        isAutoClosing = false
        idleTimer?.invalidate()
        autoCloseTimer?.invalidate()

        // Save hint only after typing, and only if there's content
        if showHint && hasContent {
            idleTimer = Timer.scheduledTimer(withTimeInterval: idleDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isIdle = true
                    self.idleTimer = Timer.scheduledTimer(withTimeInterval: self.hintDuration, repeats: false) { [weak self] _ in
                        Task { @MainActor in
                            self?.isIdle = false
                        }
                    }
                }
            }
        }

        // Auto-close after configured seconds of inactivity
        if AppSettings.autoCloseEnabled {
            autoCloseTimer = Timer.scheduledTimer(withTimeInterval: autoCloseDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.onDismiss?()
                }
            }
        }
    }

    func pauseIdle() {
        idleTimer?.invalidate()
        autoCloseTimer?.invalidate()
        isIdle = false
    }

    func addItem(_ item: CaptureItem) {
        currentSession.addItem(item)
        persistSession()
        resetIdle()
    }

    func removeItem(at item: CaptureItem) {
        currentSession.removeItem(item)
        persistSession()
    }

    /// Called with user edits (typed, pasted or dictated by Wispr Flow).
    func updateText(_ text: String) {
        var items = currentSession.items.filter {
            if case .text = $0 { return false }
            return true
        }
        if !text.isEmpty {
            items.insert(.text(text), at: 0)
        }
        currentSession = CaptureSession()
        for item in items {
            currentSession.addItem(item)
        }
        persistSession()
        resetIdle(showHint: true)
    }

    private func currentTextContent() -> String {
        for item in currentSession.items {
            if case .text(let content) = item { return content }
        }
        return ""
    }

    func cleanupWithClaude() {
        let text = currentTextContent()
        guard !text.isEmpty, !isCleaning, AppSettings.hasClaudeApiKey else { return }

        isCleaning = true
        pauseIdle()
        let claude = ClaudeService(apiKey: AppSettings.claudeApiKey)

        Task {
            if let cleaned = await claude.cleanup(text: text) {
                await MainActor.run {
                    updateText(cleaned)
                    isCleaning = false
                    resetIdle(showHint: true)
                }
            } else {
                await MainActor.run {
                    isCleaning = false
                    showToast("Cleanup failed", isError: true)
                    resetIdle()
                }
            }
        }
    }

    func save() {
        let vaultPath = AppSettings.vaultPath
        let writer = VaultWriter(vaultPath: vaultPath)

        do {
            let _ = try writer.save(session: currentSession, title: nil, folder: nil)
            showToast("Saved to vault", isError: false)
            clearSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onDismiss?()
            }
        } catch {
            showToast("Failed to save — check vault path in settings", isError: true)
        }
    }

    func discardSession() {
        clearSession()
        deletePersistence()
    }

    private func showToast(_ message: String, isError: Bool) {
        toastMessage = message
        toastIsError = isError
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: isError ? 3 : 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.toastMessage = nil
            }
        }
    }

    private func persistSession() {
        guard !currentSession.isEmpty else {
            deletePersistence()
            return
        }
        if let data = try? JSONEncoder().encode(currentSession) {
            try? data.write(to: URL(fileURLWithPath: persistencePath))
        }
    }

    private func loadPersistedSession() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: persistencePath)),
              let session = try? JSONDecoder().decode(CaptureSession.self, from: data) else {
            return
        }
        currentSession = session
    }

    private func clearSession() {
        currentSession = CaptureSession()
        deletePersistence()
    }

    private func deletePersistence() {
        try? FileManager.default.removeItem(atPath: persistencePath)
    }
}
