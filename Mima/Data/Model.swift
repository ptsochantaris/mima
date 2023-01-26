#if canImport(Cocoa)
import Cocoa
#endif
import Foundation

final class Model: ObservableObject, Codable {
    @Published var entries: ContiguousArray<ListItem>
    private var renderQueue: ContiguousArray<UUID>

    init() {
        entries = [
            ListItem(prompt: "A colorful bowl of fruit on a wooden table", negativePrompt: "Berries", seed: nil, steps: 50, guidance: 7.5, state: .creating)
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

        Task { @MainActor in
            startRenderingIfNeeded()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(renderQueue, forKey: .renderQueue)
    }

    @MainActor
    private var rendering = false
}

@MainActor
extension Model {
    func removeAllQueued() {
        entries.removeAll { $0.state.isWaiting }
        save()
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
        if let rescuedItem = entries.first(where: { $0.state.isWaiting }) {
            return rescuedItem
        }
        return nil
    }

    func startRenderingIfNeeded() {
        if rendering {
            return
        }
        rendering = true
        Task { @MainActor in
            while let entry = nextEntryToRender(), await Rendering.render(entry) {
                renderQueue.removeAll(where: { $0 == entry.id })
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
        renderQueue.append(entry.id)
        startRenderingIfNeeded()
        save()
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
            renderQueue.append(randomEntry.id)
            startRenderingIfNeeded()
            save()
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
            try JSONEncoder().encode(self).write(to: Model.indexFileUrl, options: .atomic)
            NSLog("State saved")
        } catch {
            NSLog("Error saving state: \(error)")
        }
    }

    static let shared: Model = {
        Rendering.startup()

        guard let data = try? Data(contentsOf: indexFileUrl) else {
            return Model()
        }

        do {
            return try JSONDecoder().decode(Model.self, from: data)
        } catch {
            NSLog("Error loading model: \(error.localizedDescription)")
            return Model()
        }
    }()
}
