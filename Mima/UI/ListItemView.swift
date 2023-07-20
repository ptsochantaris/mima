import SwiftUI
import UniformTypeIdentifiers

struct ItemBackground: View {
    var body: some View {
        #if canImport(Cocoa)
            Color.secondary.opacity(0.1)
        #else
            Color.secondary.opacity(0.3)
        #endif
    }
}

struct ListItemView: View, Identifiable {
    @ObservedObject private var entry: ListItem
    @State private var showPicker = false
    @State private var visibleControls = false

    var id: UUID { entry.id }

    init(entry: ListItem) {
        self.entry = entry
    }

    var body: some View {
        ZStack {
            ItemBackground()
            
            let state = entry.state
            if case let .rendering(steps, total, preview) = state, let preview {
                Image(preview, scale: 1, label: Text("")).resizable().opacity(0.3 * Double(steps) / Double(total))
            } else if !(entry.state.isDone || entry.imageName.isEmpty || entry.imagePath.isEmpty) {
                AsyncImage(url: URL(filePath: entry.imagePath)) { img in
                    img.resizable().opacity(0.12)
                } placeholder: {
                    Color.clear
                }
            }

            switch state {
            case .cloning, .creating:
                NewItem(newItemInfo: NewItemModel(prototype: entry))

            case .blocked, .queued, .rendering:
                EntryTitle(entry: entry)
                Color.clear
                    .overlay(alignment: .bottomLeading) {
                        EntryFooter(entry: entry)
                            .padding()
                    }

            case .done:
                let sourceUrl = entry.imageUrl
                AsyncImage(url: sourceUrl) { img in
                    img.resizable()
                    #if canImport(Cocoa)
                        .overlay {
                            AcceptingFirstMouse()
                        }
                    #endif
                        .onDrag {
                            let name = entry.exportFilename
                            let destUrl = URL(fileURLWithPath: NSTemporaryDirectory() + name)
                            let fm = FileManager.default
                            if fm.fileExists(atPath: destUrl.path) {
                                try? fm.removeItem(at: destUrl)
                            }
                            try? fm.copyItem(at: sourceUrl, to: destUrl)
                            let p = NSItemProvider(item: destUrl as NSSecureCoding?, typeIdentifier: UTType.fileURL.identifier)
                            p.suggestedName = name
                            return p
                        }
                } placeholder: {
                    Color.clear
                }
                .overlay(alignment: .topLeading) {
                    if visibleControls {
                        MimaButon(look: .share)
                            .onTapGesture {
                                showPicker = true
                            }
                        #if canImport(Cocoa)
                            .background(SharePicker(isPresented: $showPicker, sharingItems: [sourceUrl]))
                        #endif
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if visibleControls {
                        MimaButon(look: .encore)
                            .onTapGesture {
                                withAnimation {
                                    Model.shared.createRandomVariant(of: entry)
                                }
                            }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if visibleControls {
                        MimaButon(look: .edit)
                            .onTapGesture {
                                withAnimation {
                                    Model.shared.insertCreator(for: entry)
                                }
                            }
                    }
                }

            case .cancelled:
                Text("Cancelled")
                    .font(.caption)

            case .error:
                Text("Error generating")
                    .font(.caption)
            }
        }
        .contextMenu {
            if entry.state.isDone {
                Button("Cut") {
                    entry.copyImageToPasteboard()
                    Model.shared.delete(entry)
                }
                Button("Copy") {
                    entry.copyImageToPasteboard()
                }
            }
            if !entry.state.isCreator {
                Button(entry.state.isRendering ? "Cancel" : "Remove") {
                    Model.shared.delete(entry)
                }
            }
            if entry.state.isWaiting {
                Button("Render This Next") {
                    Model.shared.prioritise(entry)
                }
            }
        }
        #if canImport(Cocoa)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification, object: nil)) { _ in
            visibleControls = false
        }
        #endif
        .overlay(alignment: .topTrailing) {
            if !entry.state.isCreator {
                DismissButton(entry: entry, visibleControls: visibleControls)
            }
        }
        .onHover { state in
            visibleControls = state || showPicker
        }
        .aspectRatio(1, contentMode: .fill)
    }
}
