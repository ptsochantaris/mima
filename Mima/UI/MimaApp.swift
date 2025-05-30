import Maintini
import SwiftUI

#if canImport(AppKit)
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_: Notification) {
            Maintini.setup()
        }

        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            Task {
                Rendering.shutdown()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

#elseif canImport(UIKit)
    final class AppDelegate: NSObject, UIApplicationDelegate {
        func applicationDidFinishLaunching(_: UIApplication) {
            Maintini.setup()
        }

        func applicationWillTerminate(_: UIApplication) {
            Task {
                await Rendering.shutdown()
            }
        }
    }
#endif

private struct ContentView: View {
    let model: Model
    let pipeline: PipelineState

    var body: some View {
        VStack(spacing: 0) {
            if let phase = pipeline.reportedPhase.showStatus {
                PipelinePhaseView(phase: phase)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollViewReader { proxy in
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
                    Color.clear
                        .id(model.bottomId)
                        .frame(height: 0, alignment: .bottom)
                }
                .onAppear {
                    proxy.scrollTo(model.bottomId, anchor: .top)
                }
                .onReceive(NotificationCenter.default.publisher(for: .ScrollToBottom)) { notification in
                    guard let duration = notification.object as? CGFloat else { return }
                    let bottomId = model.bottomId
                    Task {
                        try? await Task.sleep(for: .milliseconds(duration * 1000))
                        let newId = model.bottomId
                        if bottomId == newId {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                proxy.scrollTo(bottomId, anchor: .top)
                            }
                        } else {
                            proxy.scrollTo(newId, anchor: .top)
                        }
                    }
                }
            }
        }
        .background {
            Rectangle()
                .fill(.quinary)
                .ignoresSafeArea()
        }
        .onDrop(of: [.image], delegate: ImageDropDelegate())
        .frame(minWidth: 360)
    }
}

@main
struct MimaApp: App {
    #if canImport(AppKit)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    #elseif canImport(UIKit)
        @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    #endif

    @Environment(\.openWindow) var openWindow
    @State private var mainIsVisible = false
    private let model = Model.shared
    private let pipelineState = PipelineState.shared

    var body: some Scene {
        WindowGroup("Mima", id: "main") {
            ContentView(model: model, pipeline: pipelineState)
                .onAppear {
                    mainIsVisible = true
                    if !UserDefaults.standard.bool(forKey: "InitialHelpShown") {
                        openWindow(id: "help")
                        UserDefaults.standard.set(true, forKey: "InitialHelpShown")
                    }
                }
                .onDisappear {
                    mainIsVisible = false
                }
        }.commands {
            CommandGroup(after: .textEditing) {
                Button("Cancel Queued Items") {
                    withAnimation {
                        model.removeAllQueued()
                    }
                }
                Menu("Remove All Items…") {
                    Button("Confirm") {
                        withAnimation {
                            model.removeAll()
                        }
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
            CommandGroup(replacing: .help) {
                Button("Mima Help") {
                    openWindow(id: "help")
                }
            }
            CommandGroup(replacing: .appSettings) {
                Menu("Engine Version…") {
                    ForEach(ModelVersion.allCases) { version in
                        let isOn = Binding<Bool>(
                            get: { version == PipelineBuilder.userSelectedVersion },
                            set: { newValue, _ in
                                guard newValue else {
                                    return
                                }
                                Task {
                                    pipelineState.shutDown()
                                    PipelineBuilder.current = PipelineBuilder(selecting: version)
                                }
                                model.cancelAllRendering()
                            }
                        )
                        Toggle(version.displayName, isOn: isOn)
                            .disabled(isOn.wrappedValue || pipelineState.reportedPhase.booting)
                    }
                }

                Menu("Option-Click Repeats…") {
                    let counts = (
                        Array(stride(from: 10, to: 100, by: 10))
                            + Array(stride(from: 100, to: 1000, by: 100))
                            + Array(stride(from: 1000, to: 10001, by: 1000))
                    )

                    ForEach(counts, id: \.self) { count in
                        let isOn = Binding<Bool>(
                            get: { model.optionClickRepetitions == count },
                            set: { if $0 { model.optionClickRepetitions = count } }
                        )
                        Toggle("\(count) times", isOn: isOn)
                    }
                }

                Menu("Preview interval…") {
                    let counts: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 6, 7, 8, 9, 10, 20, 30, 60]

                    ForEach(counts, id: \.self) { count in
                        let isOn = Binding<Bool>(
                            get: { model.previewGenerationInterval == count },
                            set: { if $0 { model.previewGenerationInterval = count } }
                        )
                        let countString = String(format: "%.1f", count)
                        Toggle("\(countString) sec", isOn: isOn)
                    }
                }

                let isOn = Binding<Bool>(
                    get: { model.useSafetyChecker },
                    set: { model.useSafetyChecker = $0 }
                )
                Toggle("Use Safety Filter", isOn: isOn)
            }
            #if canImport(AppKit)
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
            #endif
        }
        #if canImport(AppKit)
        .defaultSize(width: 1024, height: 768)
        #endif

        WindowGroup("About Mima", id: "about") {
            AboutView()
            #if canImport(AppKit)
                .onAppear {
                    Task {
                        if let wnd = NSApp.windows.first(where: { $0.title == "About Mima" }) {
                            wnd.makeKeyAndOrderFront(self)
                        }
                    }
                }
            #endif
        }
        #if canImport(AppKit)
        .windowResizability(.contentSize)
        #endif

        WindowGroup("Mima Help", id: "help") {
            HelpView()
            #if canImport(AppKit)
                .onAppear {
                    Task {
                        if let wnd = NSApp.windows.first(where: { $0.title == "Mima Help" }) {
                            wnd.makeKeyAndOrderFront(self)
                        }
                    }
                }
            #endif
        }
        #if canImport(AppKit)
        .windowResizability(.contentSize)
        #endif
    }
}
