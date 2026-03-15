// Zoidberg/AppState.swift
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var currentSession = CaptureSession()
    @Published var isDictating = false
    @Published var audioLevel: Float = 0
    /// Text that existed before the current dictation session started
    private var textBeforeDictation: String?
    @Published var isDragOver = false
    @Published var toastMessage: String?
    @Published var toastIsError = false
    @Published var openCount = 0
    @Published var isIdle = false
    @Published var isAutoClosing = false
    @Published var isDiscardHolding = false

    /// Called when the panel should close (after save, discard, etc.)
    var onDismiss: (() -> Void)?
    /// Called to stop any active dictation
    var onStopDictation: (() -> Void)?
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

    func startDictation() {
        textBeforeDictation = currentTextContent()
        isDictating = true
        idleTimer?.invalidate()
        autoCloseTimer?.invalidate()
        isIdle = false
    }

    func stopDictation() {
        isDictating = false
        resetIdle(showHint: true)
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

    /// Called with transcription text during dictation, or with user edits.
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
        if !isDictating {
            resetIdle(showHint: true)
        }
    }

    /// Called by the transcription service — appends new speech after existing text.
    func updateTranscription(_ transcribedText: String) {
        let prefix = textBeforeDictation ?? ""
        if prefix.isEmpty {
            updateText(transcribedText)
        } else {
            updateText(prefix + "\n" + transcribedText)
        }
    }

    private func currentTextContent() -> String {
        for item in currentSession.items {
            if case .text(let content) = item { return content }
        }
        return ""
    }

    func save() {
        onStopDictation?()

        let vaultPath = AppSettings.vaultPath
        let writer = VaultWriter(vaultPath: vaultPath)

        do {
            let result = try writer.save(session: currentSession, title: nil, folder: nil)
            showToast("✓ Saved to vault", isError: false)

            if AppSettings.hasClaudeApiKey {
                let session = currentSession
                let filePath = result.filePath
                Task.detached {
                    await self.enhanceInBackground(session: session, filePath: filePath, writer: writer)
                }
            }

            clearSession()
            onDismiss?()
        } catch {
            showToast("Failed to save — check vault path in settings", isError: true)
        }
    }

    private func enhanceInBackground(session: CaptureSession, filePath: String, writer: VaultWriter) async {
        let claude = ClaudeService(apiKey: AppSettings.claudeApiKey)
        guard let result = await claude.enhance(session: session) else { return }

        var enhancedSession = CaptureSession()
        for item in session.items {
            if case .text = item, let cleaned = result.cleanedText {
                enhancedSession.addItem(.text(cleaned))
            } else {
                enhancedSession.addItem(item)
            }
        }

        let enhancedMarkdown = enhancedSession.toMarkdown(title: result.title)

        try? writer.moveToEnhancedLocation(
            from: filePath,
            enhancedMarkdown: enhancedMarkdown,
            title: result.title,
            folder: result.folder
        )
    }

    func discardSession() {
        onStopDictation?()
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
        textBeforeDictation = nil
        deletePersistence()
    }

    private func deletePersistence() {
        try? FileManager.default.removeItem(atPath: persistencePath)
    }
}
