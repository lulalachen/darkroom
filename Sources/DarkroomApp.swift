import AppKit
import SwiftUI

@main
struct DarkroomApp: App {
    @StateObject private var viewModel = BrowserViewModel()
    @StateObject private var preferences = AppPreferences.shared
    
    init() {
        if let url = appIconURL(),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(preferences)
                .task {
                    await viewModel.bootstrapForExportWorkflow()
                }
        }
        .defaultSize(width: 1200, height: 720)

        Settings {
            PreferencesView()
                .environmentObject(preferences)
        }
    }

    private func appIconURL() -> URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(
            forResource: "darkroom_appicon_1024_opaque",
            withExtension: "png",
            subdirectory: "AppIcon.icon/Assets"
        )
        #else
        return Bundle.main.url(
            forResource: "darkroom_appicon_1024_opaque",
            withExtension: "png",
            subdirectory: "AppIcon.icon/Assets"
        )
        #endif
    }
}
