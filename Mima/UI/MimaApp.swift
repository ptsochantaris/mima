import SwiftUI

#if canImport(Cocoa)
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await Rendering.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#elseif canImport(UIKit)
final class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    func applicationWillTerminate(_ application: UIApplication) {
        Task {
            await Rendering.shutdown()
        }
    }
}
#endif

private struct ContentView: View {
    @ObservedObject private var model = Model.shared
    @ObservedObject private var pipeline = PipelineState.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let phase = pipeline.phase.showStatus {
                    PipelinePhaseView(phase: phase)
                }
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 300, maximum: 1024), spacing: 16)
                ], spacing: 16) {
                    ForEach(model.entries) { entry in
                        ListItemView(entry: entry)
                            .cornerRadius(21)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 360)
    }
}

@main
struct MimaApp: App {
    #if canImport(Cocoa)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    #elseif canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    #endif
    
    @Environment(\.openWindow) var openWindow
    @State private var mainIsVisible = false

    var body: some Scene {
        WindowGroup("Mima", id: "main") {
            ContentView()
                .onAppear {
                    mainIsVisible = true
                }
                .onDisappear {
                    mainIsVisible = false
                }
        }.commands {
            CommandGroup(after: .textEditing) {
                Button("Cancel Queued Items") {
                    withAnimation {
                        Model.shared.removeAllQueued()
                    }
                }
                Button("Remove All Items") {
                    withAnimation {
                        Model.shared.removeAll()
                    }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    if !mainIsVisible {
                        openWindow(id: "main")
                    }
                }
                .keyboardShortcut("n")
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Mima") {
                    openWindow(id: "about")
                }
            }
#if canImport(Cocoa)
            CommandGroup(replacing: .importExport) {
                Button("Export All Items") {
                    Task {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Export \(Model.shared.entries.count) Items"
                        if panel.runModal() == .OK {
                            if let url = panel.url {
                                Model.shared.exportAll(to: url)
                            }
                        }
                    }
                }.keyboardShortcut("e")
            }
#endif
        }
#if canImport(Cocoa)
        .defaultSize(width: 1024, height: 768)
#endif
        WindowGroup("About Mima", id: "about") {
            AboutView()
        }
#if canImport(Cocoa)
        .windowResizability(.contentSize)
#endif
    }
}
