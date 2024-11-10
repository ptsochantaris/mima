import SwiftUI
import UniformTypeIdentifiers

struct ListItemView: View, Identifiable {
    private let entry: ListItem
    @State private var showPicker = false
    @State private var visibleControls = false
    @State private var uuid = UUID()
    @State private var attemptCount = 0

    let id: UUID

    init(entry: ListItem) {
        id = entry.id
        self.entry = entry
    }

    var body: some View {
        ZStack {
            let state = entry.state
            if case let .rendering(step, total, preview) = state, let preview {
                Image(preview, scale: 1, label: Text("")).resizable().opacity(0.6 * Double(step) / Double(total))
            } else if !(entry.state.isDone || entry.imageName.isEmpty || entry.imagePath.isEmpty) {
                AsyncImage(url: URL(filePath: entry.imagePath)) { img in
                    img
                        .resizable()
                        .opacity(0.12)
                } placeholder: {
                    Color.clear
                }
                .id(entry.id.uuidString)
            }

            switch state {
            case .cloning, .creating:
                NewItem(entry: entry)

            case let .rendering(step, total, _):
                let progress = Double(step) / Double(total)
                let ongoing = progress > 0.4
                let titleOpacity = (3.4 - progress * 4)
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: ongoing ? .topLeading : .center) {
                        VStack(spacing: 8) {
                            EntryName(entry: entry, textAlignment: ongoing ? .leading : .center)
                                .opacity(titleOpacity)
                                .id(entry.id)
                            if !ongoing {
                                Spacer()
                                    .frame(height: 1)
                            }
                        }
                        .padding([.top, .bottom])
                        .padding(ongoing ? .leading : [])
                        .padding(ongoing ? .trailing : [], 50)
                        .padding(ongoing ? [] : .horizontal, 50)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if !ongoing {
                            EntryFooter(entry: entry)
                                .padding()
                        }
                    }

            case .blocked, .queued:
                VStack(spacing: 8) {
                    EntryName(entry: entry, textAlignment: .center)
                        .id(entry.id)

                    Spacer()
                        .frame(height: 1)
                }
                .padding([.top, .bottom])
                .padding(.horizontal, 50)

                Color.clear
                    .overlay(alignment: .bottomLeading) {
                        EntryFooter(entry: entry)
                            .padding()
                    }

            case .done:
                let sourceUrl = entry.imageUrl
                AsyncImage(url: sourceUrl, scale: 1, transaction: Transaction()) { phase in
                    if let error = phase.error {
                        Image(systemName: "xmark").onAppear {
                            log("Applying hack for `cancelled` phase: \(error.localizedDescription) attempt: \(attemptCount)")
                            if attemptCount < 4 {
                                uuid = UUID()
                            }
                        }
                    } else if let img = phase.image {
                        img
                            .resizable()
                        #if canImport(AppKit)
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
                            .id(entry.id.uuidString)
                    } else {
                        EmptyView()
                    }
                }
                .id(uuid)
                .overlay(alignment: .topLeading) {
                    if visibleControls {
                        MimaButon(look: .share)
                            .onTapGesture {
                                showPicker = true
                            }
                        #if canImport(AppKit)
                            .background(SharePicker(isPresented: $showPicker, sharingItems: [sourceUrl]))
                        #endif
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if visibleControls {
                        MimaButon(look: .encore)
                            .onTapGesture {
                                Model.shared.createRandomVariant(of: entry)
                            }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if visibleControls {
                        MimaButon(look: .edit)
                            .onTapGesture {
                                Model.shared.insertCreator(for: entry)
                            }
                    }
                }

            case .cancelled:
                Text("Cancelled")
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .error:
                Text("Error generating")
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            Rectangle()
                .fill(.quaternary)
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
        #if canImport(AppKit)
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
