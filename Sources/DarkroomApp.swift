import SwiftUI

@main
struct DarkroomApp: App {
    @StateObject private var viewModel = BrowserViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .defaultSize(width: 1200, height: 720)
    }
}
