import AppIntents
import Foundation

@available(macOS 13.0, *)
struct ExportWithPresetIntent: AppIntent {
    static var title: LocalizedStringResource = "Export With Preset"
    static var description = IntentDescription("Queue a Darkroom export using a preset name and destination path.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Preset Name")
    var presetName: String

    @Parameter(title: "Destination Path")
    var destinationPath: String

    @Parameter(title: "Shoot Name", default: "Session")
    var shootName: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let payload: [String: String] = [
            "presetName": presetName,
            "destinationPath": destinationPath,
            "shootName": shootName
        ]
        UserDefaults.standard.set(payload, forKey: darkroomShortcutExportRequestDefaultsKey)
        DistributedNotificationCenter.default().post(name: .darkroomShortcutExportRequested, object: nil)
        return .result(dialog: "Queued export request in Darkroom.")
    }
}

@available(macOS 13.0, *)
struct DarkroomAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ExportWithPresetIntent(),
            phrases: [
                "Run export in \(.applicationName)",
                "Start export in \(.applicationName)"
            ],
            shortTitle: "Export With Preset"
        )
    }
}
