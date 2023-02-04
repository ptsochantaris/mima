#if canImport(Cocoa)
    import Cocoa
#endif
import Foundation

final class Model: ObservableObject, Codable {
    @Published var entries: ContiguousArray<ListItem>
    @Published var tipJar = TipJar()

    private var renderQueue: ContiguousArray<UUID>
    private var rendering = false
    private static let cloningAssets = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appending(path: "cloningAssets", directoryHint: .isDirectory)

    init() {
        entries = [
            ListItem(prompt: "A colorful bowl of fruit on a wooden table", imagePath: "", originalImagePath: "", imageName: "", strength: ListItem.defaultStrength, negativePrompt: "Berries", seed: nil, steps: ListItem.defaultSteps, guidance: ListItem.defaultGuidance, state: .creating)
        ]
        renderQueue = ContiguousArray<UUID>()
    }

    enum CodingKeys: CodingKey {
        case entries
        case renderQueue
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entries = try values.decode(ContiguousArray<ListItem>.self, forKey: .entries)
        renderQueue = try values.decode(ContiguousArray<UUID>.self, forKey: .renderQueue)
        Task {
            await startRenderingIfNeeded()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(renderQueue, forKey: .renderQueue)
    }
    
    static func ingestCloningAsset(from url: URL) -> String {
        if !FileManager.default.fileExists(atPath: cloningAssets.path) {
            try? FileManager.default.createDirectory(at: cloningAssets, withIntermediateDirectories: true)
        }
        let destinationUrl = cloningAssets.appending(path: UUID().uuidString, directoryHint: .notDirectory)
        try? FileManager.default.copyItem(at: url, to: destinationUrl)
        return destinationUrl.path
    }
    
    static let shared: Model = {
        Task {
            await PipelineBootup().startup()
        }

        if let data = try? Data(contentsOf: indexFileUrl) {
            do {
                return try JSONDecoder().decode(Model.self, from: data)
            } catch {
                NSLog("Error loading model: \(error.localizedDescription)")
            }
        }
        
        return Model()
    }()
}

@MainActor
extension Model {
    func removeAllQueued() {
        entries.removeAll { $0.state.isWaiting }
        save()
    }
    
    func cancelAllRendering() {
        for entry in entries where entry.state.isRendering {
            entry.state = .queued
        }
    }

    func removeAll() {
        entries.removeAll {
            if $0.state.isCreator {
                return false
            }
            $0.nuke()
            return true
        }
        save()
    }

    func delete(_ entry: ListItem) {
        let id = entry.id
        if let i = entries.firstIndex(where: { $0.id == id }) {
            let entry = entries[i]
            entries.remove(at: i)
            entry.nuke()
        }
        save()
    }

    private func nextEntryToRender() -> ListItem? {
        while let uuid = renderQueue.first {
            if let entry = entries.first(where: { $0.id == uuid }) {
                return entry
            } else {
                // invalid entry, throw away
                renderQueue.removeFirst()
            }
        }
        return nil
    }

    func startRenderingIfNeeded() async {
        if rendering {
            NSLog("Already rendering")
            return
        }
        if renderQueue.isEmpty {
            NSLog("Nothing to render")
            return
        }
        if case .setup = await PipelineState.shared.phase {
            NSLog("Pipeline not ready")
            return
        }
        rendering = true
        Task {
            while let entry = nextEntryToRender(), await Rendering.render(entry) {
                save()
            }
            rendering = false
        }
    }

    func exportAll(to url: URL) {
        let fm = FileManager.default
        for entry in entries where entry.state.isDone {
            let destination = url.appending(path: entry.exportFilename, directoryHint: .notDirectory)
            try? fm.copyItem(at: entry.imageUrl, to: destination)
        }
        #if canImport(Cocoa)
            NSWorkspace.shared.open(url)
        #endif
    }

    private func submitToQueue(_ id: UUID) {
        renderQueue.append(id)
        Task {
            await startRenderingIfNeeded()
            save()
        }
    }

    func createItem(basedOn prototype: ListItem, fromCreator: Bool) {
        let entry = prototype.clone(as: .queued)
        if let creatorIndex = entries.firstIndex(where: { $0.id == prototype.id }) {
            if fromCreator {
                entries.insert(entry, at: creatorIndex)
            } else {
                entries[creatorIndex] = entry
            }
        } else {
            entries.insert(entry, at: 0)
        }
        submitToQueue(entry.id)
    }

    func add(entry: ListItem) {
        entries.insert(entry, at: 0)
        submitToQueue(entry.id)
    }

    func prioritise(_ item: ListItem) {
        if let index = renderQueue.firstIndex(of: item.id) {
            renderQueue.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        }
    }

    func createRandomVariant(of entry: ListItem) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let randomEntry = entry.randomVariant()
            entries.insert(randomEntry, at: index + 1)
            submitToQueue(randomEntry.id)
        }
    }

    func insertCreator(for entry: ListItem) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let newEntry = entry.clone(as: .clonedCreator)
            entries.insert(newEntry, at: index + 1)
            save()
        }
    }

    private static let indexFileUrl = fileDirectory.appending(path: "entries.json", directoryHint: .notDirectory)

    func save() {
        do {
            let entryIds = Set(entries.filter(\.state.shouldStayInRenderQueue).map(\.id))
            renderQueue.removeAll { !entryIds.contains($0) }
            try JSONEncoder().encode(self).write(to: Model.indexFileUrl, options: .atomic)
            NSLog("State saved")
        } catch {
            NSLog("Error saving state: \(error)")
        }
        
        var imagePaths = Set<String>()
        for entry in entries {
            if !entry.imagePath.isEmpty {
                imagePaths.insert(URL(filePath: entry.imagePath).lastPathComponent)
            }
        }
        let fm = FileManager.default
        let cloningAssets = Model.cloningAssets
        for item in (try? fm.contentsOfDirectory(atPath: cloningAssets.path)) ?? [] {
            if !item.hasPrefix("."), !imagePaths.contains(item) {
                try? fm.removeItem(at: cloningAssets.appending(path: item))
                NSLog("Clearing unused attachment \(item)")
            }
        }
    }
}
