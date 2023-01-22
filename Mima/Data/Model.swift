import Cocoa
import Foundation

final class Model: ObservableObject, Codable {
    @Published var entries: ContiguousArray<GalleryEntry>
    @Published var prompt: String
    @Published var negativePrompt: String
    @Published var seed: String
    @Published var steps: String
    @Published var count: String
    @Published var guidance: String

    private var renderQueue: ContiguousArray<UUID>

    @MainActor
    init() {
        entries = ContiguousArray<GalleryEntry>()
        renderQueue = ContiguousArray<UUID>()
        prompt = ""
        negativePrompt = ""
        seed = ""
        steps = ""
        count = ""
        guidance = ""
    }

    enum CodingKeys: CodingKey {
        case entries
        case renderQueue
        case prompt
        case negativePrompt
        case seed
        case steps
        case count
        case guidance
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        entries = try values.decode(ContiguousArray<GalleryEntry>.self, forKey: .entries)
        renderQueue = try values.decode(ContiguousArray<UUID>.self, forKey: .renderQueue)
        prompt = try values.decode(String.self, forKey: .prompt)
        negativePrompt = try values.decode(String.self, forKey: .negativePrompt)
        seed = try values.decode(String.self, forKey: .seed)
        steps = try values.decode(String.self, forKey: .steps)
        count = try values.decode(String.self, forKey: .count)
        guidance = try values.decode(String.self, forKey: .guidance)
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
        try container.encode(prompt, forKey: .prompt)
        try container.encode(negativePrompt, forKey: .negativePrompt)
        try container.encode(seed, forKey: .seed)
        try container.encode(steps, forKey: .steps)
        try container.encode(count, forKey: .count)
        try container.encode(guidance, forKey: .guidance)
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

    func populate(from entry: GalleryEntry) {
        prompt = String(entry.prompt)
        negativePrompt = String(entry.negativePrompt)
        seed = String(entry.seed)
        steps = String(entry.steps)
        guidance = String(entry.guidance)
    }

    func delete(_ entry: GalleryEntry) {
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

    private func nextEntryToRender() -> GalleryEntry? {
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

    func createItems() {
        var finalSeed = UInt32(seed) ?? UInt32.random(in: 0 ... UInt32.max)
        let finalPrompt = prompt.isEmpty ? "Mima" : prompt
        let finalSteps = Int(steps) ?? 50
        let finalCount = Int(count) ?? 1
        let finalGuidance = Float(guidance) ?? 7.5

        let queueWasEmpty = renderQueue.isEmpty

        for _ in 0 ..< finalCount {
            let entry = GalleryEntry(prompt: finalPrompt, negativePrompt: negativePrompt, seed: finalSeed, steps: finalSteps, guidance: finalGuidance)
            if finalSeed < Int.max {
                finalSeed += 1
            }
            entries.insert(entry, at: 0)
            renderQueue.append(entry.id)
        }

        if queueWasEmpty {
            startRendering()
        }
        save()
    }

    func createRandomVariant(of entry: GalleryEntry) {
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

    private static let indexFileUrl = fileDirectory.appending(path: "index.json", directoryHint: .notDirectory)

    func save() {
        try? JSONEncoder().encode(self).write(to: Model.indexFileUrl)
    }

    static func load() -> Model {
        startup()
        if let data = try? Data(contentsOf: indexFileUrl),
           let loaded = try? JSONDecoder().decode(Model.self, from: data) {
            return loaded
        }
        return Model()
    }
}
