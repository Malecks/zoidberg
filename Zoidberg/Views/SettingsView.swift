import SwiftUI

struct SettingsView: View {
    @State private var vaultPath = AppSettings.vaultPath
    @State private var apiKey = AppSettings.claudeApiKey ?? ""
    @State private var launchAtLogin = AppSettings.launchAtLogin

    var body: some View {
        Form {
            Section("Obsidian Vault") {
                HStack {
                    TextField("Vault Path", text: $vaultPath)
                        .textFieldStyle(.roundedBorder)
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
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Circle()
                        .fill(apiKey.isEmpty ? Color.gray : Color.green)
                        .frame(width: 8, height: 8)
                    Text(apiKey.isEmpty ? "Not configured" : "Connected")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
        .preferredColorScheme(.light)
        .onChange(of: vaultPath) { _, newValue in
            AppSettings.vaultPath = newValue
        }
        .onChange(of: apiKey) { _, newValue in
            AppSettings.claudeApiKey = newValue.isEmpty ? nil : newValue
        }
        .onChange(of: launchAtLogin) { _, newValue in
            AppSettings.launchAtLogin = newValue
        }
    }
}
