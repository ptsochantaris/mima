#if canImport(AppKit)
    import AppKit
#endif
import Foundation
import Maintini
import PopTimer
import SwiftUI

@MainActor
final class Model: ObservableObject, Codable {
    @Published var entries: ContiguousArray<ListItem> = []
    @Published var bottomId = UUID()

    private var renderQueue: ContiguousArray<UUID> = []
    private var rendering = false {
        didSet {
            if rendering != oldValue {
                if rendering {
                    Task { @MainActor in
                        Maintini.startMaintaining()
                    }
                } else {
                    Task { @MainActor in
                        Maintini.endMaintaining()
                    }
                }
            }
        }
    }

    private static let cloningAssets = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appending(path: "cloningAssets", directoryHint: .isDirectory)

    private lazy var saveTimer = PopTimer(timeInterval: 0.1) { [weak self] in
        guard let self else { return }
        saveNow()
    }

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

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let _entries = try values.decode(ContiguousArray<ListItem>.self, forKey: .entries)
        let _renderQueue = try values.decode(ContiguousArray<UUID>.self, forKey: .renderQueue)
        MainActor.assumeIsolated {
            entries = _entries
            renderQueue = _renderQueue
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        let (_entries, _renderQueue) = MainActor.assumeIsolated { (entries, renderQueue) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_entries, forKey: .entries)
        try container.encode(_renderQueue, forKey: .renderQueue)
    }

    static func ingestCloningAsset(from url: URL) -> String {
        if !FileManager.default.fileExists(atPath: cloningAssets.path) {
            try? FileManager.default.createDirectory(at: cloningAssets, withIntermediateDirectories: true)
        }
        let destinationUrl = cloningAssets.appending(path: UUID().uuidString, directoryHint: .notDirectory)
        let image = loadImage(from: url)?.scaled(to: PipelineBuilder.userSelectedVersion.imageSize)
        image?.save(to: destinationUrl)
        return destinationUrl.path
    }

    static let shared: Model = {
        PipelineBuilder.current = PipelineBuilder()

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

        return model
    }()
}

@MainActor
extension Model {
    var optionClickRepetitions: Int {
        get {
            let count = UserDefaults.standard.integer(forKey: "optionClickRepetitions")
            return count == 0 ? 10 : count
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "optionClickRepetitions")
            objectWillChange.send()
        }
    }

    var previewGenerationInterval: Double {
        get {
            let period = UserDefaults.standard.double(forKey: "previewGenerationPeriod")
            return period == 0 ? 2 : period
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "previewGenerationPeriod")
            objectWillChange.send()
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
        #if canImport(AppKit)
            NSWorkspace.shared.open(url)
        #endif
    }

    private func submitToQueue(_ ids: [UUID]) async {
        renderQueue.append(contentsOf: ids)
        await startRenderingIfNeeded()
        save()
    }

    func createItem(basedOn prototype: ListItem, count: Int, scroll: Bool) async {
        guard let creatorIndex = entries.firstIndex(where: { $0.id == prototype.id }) else {
            return
        }
        let newItems = (0 ..< count).map { _ in prototype.clone(as: .queued) }
        withAnimation(.easeInOut(duration: 0.2)) {
            entries.insert(contentsOf: newItems, at: creatorIndex)
            if scroll {
                bottomId = UUID()
                NotificationCenter.default.post(name: .ScrollToBottom, object: 0.2)
            }
        }

        await submitToQueue(newItems.map(\.id))
    }

    func replaceItem(basedOn prototype: ListItem) async {
        guard let creatorIndex = entries.firstIndex(where: { $0.id == prototype.id }) else {
            return
        }

        let newItem = prototype.clone(as: .queued)
        withAnimation(.easeInOut(duration: 0.2)) {
            entries[creatorIndex] = newItem
        }
        await submitToQueue([newItem.id])
    }

    func state(of entity: ListItem) -> ListItem.State? {
        entries.first { $0.id == entity.id }?.state
    }

    func addAndRender(entry: ListItem) async {
        await add(entry: entry)
        await submitToQueue([entry.id])
    }

    func add(entry: ListItem) async {
        guard let creatorIndex = entries.firstIndex(where: { $0.state.isCreator }) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            entries.insert(entry, at: creatorIndex)
            bottomId = UUID()
            NotificationCenter.default.post(name: .ScrollToBottom, object: 0.2)
        }
    }

    func prioritise(_ item: ListItem) {
        if let index = renderQueue.firstIndex(of: item.id) {
            renderQueue.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        }
    }

    func createRandomVariant(of entry: ListItem) async {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }
        #if canImport(AppKit)
            let count = NSEvent.modifierFlags.contains(.option) ? Model.shared.optionClickRepetitions : 1
        #else
            let count = 1
        #endif
        let newEntries = (0 ..< count).map { _ in entry.randomVariant() }

        withAnimation(.easeInOut(duration: 0.2)) {
            entries.insert(contentsOf: newEntries, at: index + 1)
        }
        await submitToQueue(newEntries.map(\.id))
    }

    func insertCreator(for entry: ListItem) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let newEntry = entry.clone(as: .cloning(needsFlash: true))
            withAnimation(.easeInOut(duration: 0.2)) {
                entries.insert(newEntry, at: index + 1)
            }
            save()
        }
    }

    private static let indexFileUrl = fileDirectory.appending(path: "entries.json", directoryHint: .notDirectory)

    func save() {
        let entryIds = Set(entries.filter(\.state.shouldStayInRenderQueue).map(\.id))
        renderQueue.removeAll { !entryIds.contains($0) }
        saveTimer.push()
    }

    func saveNow() {
        saveTimer.abort()
        do {
            try JSONEncoder().encode(self).write(to: Model.indexFileUrl, options: .atomic)
            log("State saved")
        } catch {
            log("Error saving state: \(error)")
        }

        var imagePaths = Set<String>()
        for entry in entries where !entry.imagePath.isEmpty {
            imagePaths.insert(URL(filePath: entry.imagePath).lastPathComponent)
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
