import SwiftUI
import UniformTypeIdentifiers

struct ListItemView: View {
    @ObservedObject private var entry: ListItem
    @State private var showPicker = false

    init(entry: ListItem) {
        self.entry = entry
    }

    @State private var visibleControls = false

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            switch entry.state {
            case .clonedCreator, .creating:
                NewItem(prototype: entry)

            case .queued:
                EntryTitle(entry: entry)
                Color.clear
                    .overlay(alignment: .bottomLeading) {
                        EntryFooter(entry: entry)
                            .padding()
                    }

            case .warmup:
                EntryTitle(entry: entry)
                Color.clear
                    .overlay(alignment: .bottomLeading) {
                        EntryFooter(entry: entry)
                            .padding()
                    }
                    .overlay(alignment: .topLeading) {
                        HStack {
                            Image(systemName: "clock")
                                .resizable()
                                .frame(width: 23, height: 23)
                            VStack(alignment: .leading) {
                                Text("Warming up the engine…")
                                Text("This takes very long the first time!")
                            }
                        }
                        .foregroundStyle(.tint)
                        .multilineTextAlignment(.center)
                        .font(.footnote)
                        .padding()
                    }

            case .rendering:
                EntryTitle(entry: entry)
                Color.clear
                    .overlay(alignment: .bottomLeading) {
                        EntryFooter(entry: entry)
                            .padding()
                    }

            case .done:
                let sourceUrl = entry.imageUrl
                AsyncImage(url: sourceUrl) { phase in
                    switch phase {
                    case let .success(img):
                        img.resizable()
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
                    case .empty, .failure:
                        Spacer()
                    @unknown default:
                        Spacer()
                    }
                }
                .overlay(alignment: .topLeading) {
                    if visibleControls {
                        MimaButon(look: .share)
                            .onTapGesture {
                                showPicker = true
                            }
                            .background(SharePicker(isPresented: $showPicker, sharingItems: [sourceUrl]))
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
            Button("Cut") {
                entry.copyImageToPasteboard()
                Model.shared.delete(entry)
            }
            Button("Copy") {
                entry.copyImageToPasteboard()
            }
            Button("Delete") {
                Model.shared.delete(entry)
            }
            Button("Render This Next") {
                Model.shared.prioritise(entry)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification, object: nil)) { _ in
            visibleControls = false
        }
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

struct DismissButton: View {
    @ObservedObject private var entry: ListItem
    private let visibleControls: Bool

    init(entry: ListItem, visibleControls: Bool) {
        self.entry = entry
        self.visibleControls = visibleControls
    }

    var body: some View {
        switch entry.state {
        case .cancelled, .clonedCreator, .creating, .error, .queued, .warmup:
            MimaButon(look: .dismiss)
                .onTapGesture {
                    withAnimation {
                        Model.shared.delete(entry)
                    }
                }

        case let .rendering(step, total):
            ZStack {
                ProgressView(value: step, total: total)
                    .progressViewStyle(GaugeProgressStyle())
                    .frame(width: 26, height: 26)
                MimaButon(look: .dismiss)
                    .onTapGesture {
                        withAnimation {
                            Model.shared.delete(entry)
                        }
                    }
            }

        case .done:
            if visibleControls {
                MimaButon(look: .dismiss)
                    .onTapGesture {
                        withAnimation {
                            Model.shared.delete(entry)
                        }
                    }
            }
        }
    }
}
