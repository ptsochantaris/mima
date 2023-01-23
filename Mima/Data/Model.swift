import Cocoa
import Foundation

final class Model: ObservableObject, Codable {
    @Published var entries: ContiguousArray<ListItem>
    private var renderQueue: ContiguousArray<UUID>

    @MainActor
    init() {
        entries = [
            ListItem(prompt: "A bowl of fruit", negativePrompt: "", seed: 0, steps: 50, guidance: 7.5, state: .creating)
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
                
        if !renderQueue.isEmpty {
            Task { @MainActor in
                startRendering()
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(renderQueue, forKey: .renderQueue)
    }
}

@MainActor
extension Model {
    func removeAllQueued() {
        entries.removeAll { $0.state.isWaiting }
        save()
    }

    func removeAll() {
        for entry in entries {
            entry.nuke()
        }
        entries.removeAll()
        save()
    }

    func delete(_ entry: ListItem) {
        let id = entry.id
        let wasWarmingUp = entry.state.isWarmup
        if let i = entries.firstIndex(where: { $0.id == id }) {
            let entry = entries[i]
            entries.remove(at: i)
            entry.nuke()
        }
        if wasWarmingUp, let nextEntry = nextEntryToRender() {
            nextEntry.state = .warmup
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

    private func startRendering() {
        Task {
            while let entry = nextEntryToRender() {
                await entry.render()
                renderQueue.removeFirst()
                save()
            }
        }
    }

    func exportAll(to url: URL) {
        let fm = FileManager.default
        for entry in entries where entry.state.isDone {
            let destination = url.appending(path: entry.exportFilename, directoryHint: .notDirectory)
            try? fm.copyItem(at: entry.imageUrl, to: destination)
        }
        NSWorkspace.shared.open(url)
    }

    func createItems(count: Int, basedOn prototype: ListItem) {
        let queueWasEmpty = renderQueue.isEmpty
        for i in 0 ..< count {
            let entry = ListItem(prompt: prototype.prompt, negativePrompt: prototype.negativePrompt, seed: prototype.seed + UInt32(i), steps: prototype.steps, guidance: prototype.guidance, state: .queued)
            if let creatorIndex = entries.firstIndex(where: { $0.id == prototype.id }) {
                entries.insert(entry, at: creatorIndex)
            } else {
                entries.insert(entry, at: 0)
            }
            renderQueue.append(entry.id)
        }

        if queueWasEmpty {
            startRendering()
        }
        save()
    }

    func createRandomVariant(of entry: ListItem) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let randomEntry = entry.randomVariant()
            entries.insert(randomEntry, at: index + 1)
            let queueWasEmpty = renderQueue.isEmpty
            renderQueue.append(randomEntry.id)
            if queueWasEmpty {
                startRendering()
            }
            save()
        }
    }

    private static let indexFileUrl = fileDirectory.appending(path: "mima.json", directoryHint: .notDirectory)

    func save() {
        do {
            try JSONEncoder().encode(self).write(to: Model.indexFileUrl)
        } catch {
            NSLog("Error saving state: \(error)")
        }
    }

    static func load() -> Model {
        startup()
        guard let data = try? Data(contentsOf: indexFileUrl) else {
            return Model()
        }
        
        do {
            return try JSONDecoder().decode(Model.self, from: data)
        } catch {
            NSLog("Error loading model: \(error.localizedDescription)")
            return Model()
        }
    }
}
