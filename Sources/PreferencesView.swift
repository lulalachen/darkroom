import AppKit
import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Form {
            Section("Caching") {
                LabeledContent("Thumbnail Cache") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(preferences.cacheSizeMB) },
                                set: { preferences.cacheSizeMB = Int($0.rounded()) }
                            ),
                            in: 128...4096,
                            step: 64
                        )
                        Text("\(preferences.cacheSizeMB) MB")
                            .frame(width: 90, alignment: .trailing)
                    }
                    .frame(width: 360)
                }
                LabeledContent("Full Image Cache") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(preferences.fullImageCacheCount) },
                                set: { preferences.fullImageCacheCount = Int($0.rounded()) }
                            ),
                            in: 16...1000,
                            step: 8
                        )
                        Text("\(preferences.fullImageCacheCount) items")
                            .frame(width: 90, alignment: .trailing)
                    }
                    .frame(width: 360)
                }
            }

            Section("Workflow") {
                Picker("Shortcut Profile", selection: $preferences.shortcutProfile) {
                    ForEach(KeyboardShortcutProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Diagnostics") {
                Toggle("Enable telemetry logs (local)", isOn: $preferences.telemetryEnabled)
            }

            Section("Library") {
                HStack(spacing: 8) {
                    TextField("Default library path", text: $preferences.defaultLibraryPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") {
                        chooseLibraryPath()
                    }
                }
                Text("Leave empty to use ~/Pictures/DarkroomLibrary.darkroom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(minWidth: 720, minHeight: 420)
    }

    private func chooseLibraryPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select parent folder for DarkroomLibrary.darkroom"
        if panel.runModal() == .OK, let url = panel.url {
            preferences.defaultLibraryPath = url.path
        }
    }
}
