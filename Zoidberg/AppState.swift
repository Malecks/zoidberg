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
    @Published var lastDiscardedSession: CaptureSession?
    @Published var showUndoDiscard = false
    @Published var openCount = 0

    /// Called when the panel should close (after save, discard, etc.)
    var onDismiss: (() -> Void)?

    private var discardTimer: Timer?
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

    func startDictation() {
        // Snapshot existing text so new transcription appends after it
        textBeforeDictation = currentTextContent()
        isDictating = true
    }

    func stopDictation() {
        isDictating = false
    }

    func addItem(_ item: CaptureItem) {
        currentSession.addItem(item)
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
        lastDiscardedSession = currentSession
        showUndoDiscard = true
        clearSession()
        deletePersistence()
        onDismiss?()

        discardTimer?.invalidate()
        discardTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.lastDiscardedSession = nil
                self?.showUndoDiscard = false
            }
        }
    }

    func undoDiscard() {
        guard let session = lastDiscardedSession else { return }
        currentSession = session
        lastDiscardedSession = nil
        showUndoDiscard = false
        discardTimer?.invalidate()
        persistSession()
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
