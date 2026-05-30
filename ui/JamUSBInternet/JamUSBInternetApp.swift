import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: AppViewModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel else { return .terminateNow }
        if viewModel.applicationShouldTerminate() {
            return .terminateNow
        }
        return .terminateCancel
    }
}

@main
struct JamUSBInternetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    appDelegate.viewModel = viewModel
                    viewModel.onAppear()
                }
                .onDisappear {
                    viewModel.onDisappear()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 760, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
