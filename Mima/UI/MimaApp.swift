import SwiftUI

// save all
// share button

struct ContentView: View {
    @ObservedObject private var model: Model

    init(model: Model) {
        self.model = model
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 300, maximum: 1024), spacing: 16)
            ], spacing: 16) {
                ForEach(model.entries) { entry in
                    ListItemView(entry: entry, model: model)
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
    @StateObject private var model = Model.load()
    @Environment(\.openWindow) var openWindow
    
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }.commands {
            CommandGroup(replacing: .newItem, addition: {})
            CommandGroup(after: .textEditing) {
                Button("Cancel Queued Items") {
                    withAnimation {
                        model.removeAllQueued()
                    }
                }
                Button("Remove All Items") {
                    withAnimation {
                        model.removeAll()
                    }
                }
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
                        panel.prompt = "Export \(model.entries.count) Items"
                        if panel.runModal() == .OK {
                            if let url = panel.url {
                                model.exportAll(to: url)
                            }
                        }
                    }
                }.keyboardShortcut("e")
            }
        }
        .defaultSize(width: 1024, height: 768)
        
        Window("About Mima", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
