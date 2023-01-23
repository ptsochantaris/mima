import SwiftUI
import UniformTypeIdentifiers

struct ListItemView: View {
    @ObservedObject private var entry: ListItem
    private let model: Model
    @State private var showPicker = false

    init(entry: ListItem, model: Model) {
        self.entry = entry
        self.model = model
    }

    @State private var visibleControls = false

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            switch entry.state {
            case .creating, .clonedCreator:
                NewItem(prototype: entry, model: model)

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
                                    model.createRandomVariant(of: entry)
                                }
                            }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if visibleControls {
                        MimaButon(look: .edit)
                            .onTapGesture {
                                withAnimation {
                                    model.insertCreator(for: entry)
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
            Button("Render This Next") {
                model.prioritise(entry)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification, object: nil)) { _ in
            visibleControls = false
        }
        .overlay(alignment: .topTrailing) {
            if !entry.state.isCreator {
                DismissButton(entry: entry, model: model, visibleControls: visibleControls)
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
    private let model: Model
    private let visibleControls: Bool
    
    init(entry: ListItem, model: Model, visibleControls: Bool) {
        self.entry = entry
        self.model = model
        self.visibleControls = visibleControls
    }
    
    var body: some View {
        switch entry.state {
        case .queued, .warmup, .clonedCreator, .cancelled, .error, .creating:
            MimaButon(look: .dismiss)
                .onTapGesture {
                    withAnimation {
                        model.delete(entry)
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
                            model.delete(entry)
                        }
                    }
            }
            
        case .done:
            if visibleControls {
                MimaButon(look: .dismiss)
                    .onTapGesture {
                        withAnimation {
                            model.delete(entry)
                        }
                    }
            }
        }
    }
}
