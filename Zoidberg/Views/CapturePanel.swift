import SwiftUI

struct CapturePanel: View {
    @ObservedObject var appState: AppState
    @State private var textInput = ""
    @State private var escapeHoldTimer: Timer?
    @State private var isHoldingEscape = false
    @State private var micHover = false
    @State private var borderRotation: Double = -0.5
    @State private var borderOpacity: Double = 0
    var onToggleDictation: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            textArea
                .frame(minHeight: 40)
            // Attachments + footer with drop zone overlay
            VStack(spacing: 0) {
                attachmentsArea
                Spacer(minLength: 0)
                if let toast = appState.toastMessage {
                    ToastView(message: toast, isError: appState.toastIsError)
                }
                footer
            }
            .frame(minHeight: 60)
            .overlay {
                if appState.isDragOver {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4])
                        )
                        .foregroundColor(.blue.opacity(0.5))
                        .background(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .fill(Color.blue.opacity(0.05))
                        )
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .padding(.top, 4)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.15), value: appState.isDragOver)
                }
            }
        }
        .frame(width: 340)
        .frame(minHeight: 80)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: NSColor(red: 0.06, green: 0.04, blue: 0.1, alpha: 1)))
        // Shimmer border inside the panel, drawn against dark background
        .overlay(
            ZStack {
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.4),
                        Color.purple.opacity(0.05),
                        Color.blue.opacity(0.3),
                        Color.purple.opacity(0.05),
                    ],
                    startPoint: UnitPoint(x: borderRotation - 0.5, y: 0),
                    endPoint: UnitPoint(x: borderRotation + 0.5, y: 1)
                )
            }
            .mask(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .strokeBorder(lineWidth: 1.5)
            )
            .opacity(appState.isDragOver ? 0 : borderOpacity)
        )
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        // Dark outer border to sandwich the shimmer against a dark background
        .padding(1.5)
        .background(
            RoundedRectangle(cornerRadius: 41.5, style: .continuous)
                .fill(Color(nsColor: NSColor(red: 0.06, green: 0.04, blue: 0.1, alpha: 1)))
        )
        .overlay(
            appState.isDragOver ?
                RoundedRectangle(cornerRadius: 41.5, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.8), lineWidth: 2)
            : nil
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .onDrop(of: [.fileURL, .url], isTargeted: $appState.isDragOver) { providers in
            handleDrop(providers)
        }
        .background(
            Button("") { appState.save() }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
        )
        .onAppear {
            textInput = currentTextContent()
        }
        .onChange(of: appState.isDragOver) { _, isDragging in
            if isDragging {
                appState.pauseIdle()
            } else {
                appState.resetIdle()
            }
        }
        .onChange(of: appState.openCount) { _, _ in
            // Reset without animation, then sweep on next frame
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                borderRotation = -0.5
                borderOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.3)) {
                    borderOpacity = 1
                }
                withAnimation(.easeInOut(duration: 1.2)) {
                    borderRotation = 1.5
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.8)) {
                        borderOpacity = 0.3
                    }
                }
            }
        }
        .onChange(of: appState.currentSession.items) { _, _ in
            let latest = currentTextContent()
            if latest != textInput {
                textInput = latest
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            // Mic button — stays in place, changes color
            Button(action: { onToggleDictation?() }) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(appState.isDictating ? .red : (micHover ? .white : .white.opacity(0.5)))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(micHover && !appState.isDictating ? Color.white.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { micHover = $0 }

            // Waveform fades in when dictating
            if appState.isDictating {
                AudioWaveView(level: appState.audioLevel)
                    .transition(.opacity)
            }

            Spacer()

            // Status text
            if let status = statusText {
                Text(status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(statusColor)
                    .transition(.opacity)
            }

            Image(systemName: "cpu")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isDictating)
        .animation(.easeInOut(duration: 0.5), value: statusText)
        .animation(.easeInOut(duration: 0.5), value: appState.isIdle)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var statusText: String? {
        if appState.isDragOver {
            return "drop here"
        }
        if appState.toastMessage != nil {
            return appState.toastIsError ? "error" : "saved"
        }
        if appState.isDictating {
            return "listening"
        }
        if appState.isIdle && appState.hasContent {
            return "⌘ ↩ to save"
        }
        return nil
    }

    private var statusColor: Color {
        if appState.isDragOver { return .blue }
        if appState.toastMessage != nil { return appState.toastIsError ? .red : .green }
        if appState.isDictating { return .red }
        if appState.isIdle { return .green }
        return .white.opacity(0.4)
    }

    private func headerButton(icon: String, isHovered: Binding<Bool>, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered.wrappedValue ? .white : .white.opacity(0.5))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered.wrappedValue ? Color.white.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered.wrappedValue = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered.wrappedValue)
    }

    private var textArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.showUndoDiscard {
                Button("Undo discard") {
                    appState.undoDiscard()
                    textInput = currentTextContent()
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.blue)
                .padding(.bottom, 4)
            }
            TextEditor(text: $textInput)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 48, maxHeight: 260)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: textInput) { _, newValue in
                    appState.updateText(newValue)
                }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    private var attachmentsArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(nonTextItems().enumerated()), id: \.offset) { index, item in
                CaptureItemRow(item: item, onDelete: {
                    appState.removeItem(at: item)
                })
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, nonTextItems().isEmpty ? 0 : 4)
        .padding(.bottom, nonTextItems().isEmpty ? 0 : 4)
    }

    private func currentTextContent() -> String {
        for item in appState.currentSession.items {
            if case .text(let content) = item { return content }
        }
        return ""
    }

    private func nonTextItems() -> [CaptureItem] {
        appState.currentSession.items.filter {
            if case .text = $0 { return false }
            return true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url, url.isFileURL else { return }
                    let filename = url.lastPathComponent
                    let path = url.path
                    let ext = url.pathExtension.lowercased()
                    Task { @MainActor in
                        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(ext) {
                            appState.addItem(.image(filename: filename, originalPath: path))
                        } else if ["mov", "mp4", "m4v", "avi", "mkv"].contains(ext) {
                            appState.addItem(.video(filename: filename, originalPath: path))
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.url") {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url,
                          url.scheme == "http" || url.scheme == "https" else { return }
                    Task { @MainActor in
                        appState.addItem(.link(url))
                    }
                }
            }
        }
        return true
    }
}

