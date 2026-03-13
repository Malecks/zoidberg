import SwiftUI

struct CapturePanel: View {
    @ObservedObject var appState: AppState
    @State private var textInput = ""
    @State private var escapeHoldTimer: Timer?
    @State private var isHoldingEscape = false
    var onToggleDictation: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            contentArea
            if let toast = appState.toastMessage {
                ToastView(message: toast, isError: appState.toastIsError)
            }
        }
        .frame(width: 320)
        .background(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(appState.isDragOver ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.fileURL, .url], isTargeted: $appState.isDragOver) { providers in
            handleDrop(providers)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            textInput = currentTextContent()
        }
    }

    private var header: some View {
        HStack {
            Text("🤖")
                .font(.system(size: 14))
            Spacer()
            if appState.isDictating {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("Listening")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            } else {
                Button(action: { onToggleDictation?() }) {
                    Image(systemName: "mic")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            Button(action: { appState.save() }) {
                Image(systemName: "checkmark")
                    .foregroundColor(.gray)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if appState.showUndoDiscard {
                    Button("Undo discard") {
                        appState.undoDiscard()
                        textInput = currentTextContent()
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                    .padding(.bottom, 4)
                }
                TextEditor(text: $textInput)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60, maxHeight: 200)
                    .onChange(of: textInput) { _, newValue in
                        appState.updateText(newValue)
                    }
                ForEach(Array(nonTextItems().enumerated()), id: \.offset) { _, item in
                    CaptureItemRow(item: item)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(minHeight: 120, maxHeight: 300)
        .opacity(appState.isDragOver ? 0.5 : 1)
        .overlay(
            appState.isDragOver ?
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundColor(.blue)
                .padding(8)
            : nil
        )
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
                provider.loadItem(forTypeIdentifier: "public.file-url") { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    let filename = url.lastPathComponent
                    let path = url.path
                    Task { @MainActor in
                        let ext = url.pathExtension.lowercased()
                        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(ext) {
                            appState.addItem(.image(filename: filename, originalPath: path))
                        } else if ["mov", "mp4", "m4v", "avi", "mkv"].contains(ext) {
                            appState.addItem(.video(filename: filename, originalPath: path))
                        }
                    }
                }
            }
            if provider.hasItemConformingToTypeIdentifier("public.url") {
                provider.loadItem(forTypeIdentifier: "public.url") { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
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
