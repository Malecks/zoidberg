import SwiftUI

struct SettingsView: View {
    @State private var vaultPath = AppSettings.vaultPath
    @State private var apiKey = AppSettings.claudeApiKey ?? ""
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var launchAtLogin = AppSettings.launchAtLogin
    @State private var autoCloseEnabled = AppSettings.autoCloseEnabled
    @State private var autoCloseSeconds = AppSettings.autoCloseSeconds

    enum ConnectionStatus {
        case unknown, testing, connected, failed
    }

    var body: some View {
        Form {
            Section("Obsidian Vault") {
                HStack {
                    Text(vaultPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
//                        .textFieldStyle(.roundedBorder)
                    Spacer()
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            vaultPath = url.path
                        }
                    }
                }
            }
            Section("Claude API") {
                HStack {
                    Text(maskedKey)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if apiKey.isEmpty {
                        Button("Paste from Clipboard") {
                            if let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
                                apiKey = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                                AppSettings.claudeApiKey = apiKey
                                testConnection()
                            }
                        }
                    } else {
                        Button("Remove") {
                            apiKey = ""
                            AppSettings.claudeApiKey = nil
                            connectionStatus = .unknown
                        }
                        .foregroundColor(.red)
                    }
                }
                if connectionStatus != .unknown || apiKey.isEmpty {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        if connectionStatus == .testing {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Auto-close after inactivity", isOn: $autoCloseEnabled)
                if autoCloseEnabled {
                    HStack {
                        Text("Close after")
                        TextField("", value: $autoCloseSeconds, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("seconds")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
        .onChange(of: vaultPath) { _, newValue in
            AppSettings.vaultPath = newValue
        }
        .onChange(of: launchAtLogin) { _, newValue in
            AppSettings.launchAtLogin = newValue
        }
        .onChange(of: autoCloseEnabled) { _, newValue in
            AppSettings.autoCloseEnabled = newValue
        }
        .onChange(of: autoCloseSeconds) { _, newValue in
            AppSettings.autoCloseSeconds = max(5, newValue)
        }
    }

    private var maskedKey: String {
        guard !apiKey.isEmpty else { return "No key configured" }
        let prefix = String(apiKey.prefix(16))
        return prefix + "••••••••"
    }

    private var statusColor: Color {
        switch connectionStatus {
        case .unknown: return .gray
        case .testing: return .yellow
        case .connected: return .green
        case .failed: return .red
        }
    }

    private var statusText: String {
        switch connectionStatus {
        case .unknown: return apiKey.isEmpty ? "Not configured" : ""
        case .testing: return "Testing connection..."
        case .connected: return "Connected"
        case .failed: return "Connection failed — check your key"
        }
    }

    private func testConnection() {
        guard !apiKey.isEmpty else {
            connectionStatus = .unknown
            return
        }
        connectionStatus = .testing

        Task {
            let url = URL(string: "https://api.anthropic.com/v1/messages")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let body: [String: Any] = [
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 1,
                "messages": [["role": "user", "content": "hi"]]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                await MainActor.run {
                    connectionStatus = status == 200 ? .connected : .failed
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed
                }
            }
        }
    }
}
