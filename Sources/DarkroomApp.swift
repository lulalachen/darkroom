import AppKit
import SwiftUI

@main
struct DarkroomApp: App {
    @StateObject private var viewModel = BrowserViewModel()
    
    init() {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .task {
                    await viewModel.prepareLibraryIfNeeded()
                }
        }
        .defaultSize(width: 1200, height: 720)
    }
}
