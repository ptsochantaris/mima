import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await Rendering.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

private struct ContentView: View {
    @ObservedObject private var model = Model.shared

    var body: some View {
        ScrollView {
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
        .frame(minWidth: 360)
    }
}

@main
struct MimaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
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
        }
        .defaultSize(width: 1024, height: 768)
        
        WindowGroup("About Mima", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
