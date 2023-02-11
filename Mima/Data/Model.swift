#if canImport(Cocoa)
    import Cocoa
#endif
import Foundation
import SwiftUI
import AsyncAlgorithms

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
        let image = loadImage(from: url)?.scaled(to: 512)
        image?.save(to: destinationUrl)
        return destinationUrl.path
    }

    static let shared: Model = {
        Task {
            await PipelineBootup().startup()
        }

        let model: Model
        if let data = try? Data(contentsOf: indexFileUrl) {
            do {
                model = try JSONDecoder().decode(Model.self, from: data)
            } catch {
                log("Error loading model: \(error.localizedDescription)")
                model = Model()
            }
        } else {
            model = Model()
        }

        Task {
            await model.startRenderingIfNeeded()
        }

        Task {
            await model.animationLockQueue.send(())
        }
        return model
    }()
    
    // This shouldn't be needed, but SwiftUI scrollview scroll-to-bottom + model animations don't get along
    private var animationLockQueue = AsyncChannel<Void>()
    private var creationQueueCount = 0
}

@MainActor
extension Model {
    func getCreationLock() async {
        for await _ in animationLockQueue {
            return
        }
    }
    
    func releaseCreationLock() {
        Task {
            await animationLockQueue.send(())
        }
    }
    
    var useSafetyChecker: Bool {
        get {
            UserDefaults.standard.bool(forKey: "useSafetyChecker")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "useSafetyChecker")
            objectWillChange.send()
        }
    }

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
            log("Already rendering")
            return
        }
        if renderQueue.isEmpty {
            log("Nothing to render")
            return
        }
        if case .setup = await PipelineState.shared.phase {
            log("Pipeline not ready")
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
        Task {
            creationQueueCount += 1
            await getCreationLock()
            if let creatorIndex = entries.firstIndex(where: { $0.id == prototype.id }) {
                let duration = creationQueueCount == 1 ? CGFloat(0.25) : CGFloat(0.1)
                let entry = prototype.clone(as: .queued)
                if fromCreator {
                    withAnimation(.easeInOut(duration: duration)) {
                        entries.insert(entry, at: creatorIndex)
                    }
                    try? await Task.sleep(for: .milliseconds(Int(duration * 1000) + 10))
                    let duration = creationQueueCount == 1 ? CGFloat(0.2) : CGFloat(0.03)
                    NotificationCenter.default.post(name: .ScrollToBottom, object: duration)
                } else {
                    withAnimation {
                        entries[creatorIndex] = entry
                    }
                }
                submitToQueue(entry.id)
            }
            creationQueueCount -= 1
            releaseCreationLock()
        }
    }

    func add(entry: ListItem) {
        Task {
            await getCreationLock()
            let duration = CGFloat(0.3)
            if let creatorIndex = entries.firstIndex(where: { $0.state.isCreator }) {
                withAnimation(.easeInOut(duration: duration)) {
                    entries.insert(entry, at: creatorIndex)
                }
                try? await Task.sleep(for: .milliseconds(Int(duration * 1000) + 10))
                NotificationCenter.default.post(name: .ScrollToBottom, object: duration)
            }
            releaseCreationLock()
        }
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
            let newEntry = entry.clone(as: .cloning(needsFlash: true))
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
            log("State saved")
        } catch {
            log("Error saving state: \(error)")
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
                log("Clearing unused attachment \(item)")
            }
        }
    }
}
