#if canImport(AppKit)
    import AppKit
#endif
import Foundation
import Maintini
import PopTimer
import SwiftUI

@MainActor @Observable
final class Model: Codable {
    var entries: ContiguousArray<ListItem> = []
    var bottomId = UUID()

    private var renderQueue: ContiguousArray<UUID> = []
    private var rendering = false {
        didSet {
            if rendering != oldValue {
                if rendering {
                    Task {
                        Maintini.startMaintaining()
                    }
                } else {
                    Task {
                        Maintini.endMaintaining()
                    }
                }
            }
        }
    }

    private static let cloningAssets = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appending(path: "cloningAssets", directoryHint: .isDirectory)

    @ObservationIgnored
    private lazy var saveTimer = PopTimer(timeInterval: 0.1) { [weak self] in
        guard let self else { return }
        saveNow()
    }

    init() {
        entries = [
            ListItem(prompt: "A colorful bowl of fruit on a wooden table", imagePath: "", originalImagePath: "", imageName: "", strength: ListItem.defaultStrength, negativePrompt: "Berries", seed: nil, steps: ListItem.defaultSteps, guidance: ListItem.defaultGuidance, state: .creating)
        ]
        renderQueue = ContiguousArray<UUID>()

        restoreSettings()
    }

    private func restoreSettings() {
        let count = UserDefaults.standard.integer(forKey: "optionClickRepetitions")
        optionClickRepetitions = count == 0 ? 10 : count

        let period = UserDefaults.standard.double(forKey: "previewGenerationPeriod")
        previewGenerationInterval = period == 0 ? 2 : period

        useSafetyChecker = UserDefaults.standard.bool(forKey: "useSafetyChecker")
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
            restoreSettings()
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

        model.startRenderingIfNeeded()

        return model
    }()

    var optionClickRepetitions = 10 {
        didSet {
            UserDefaults.standard.set(optionClickRepetitions, forKey: "optionClickRepetitions")
        }
    }

    var previewGenerationInterval: Double = 2 {
        didSet {
            UserDefaults.standard.set(previewGenerationInterval, forKey: "previewGenerationPeriod")
        }
    }

    var useSafetyChecker = false {
        didSet {
            UserDefaults.standard.set(useSafetyChecker, forKey: "useSafetyChecker")
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

    func startRenderingIfNeeded() {
        if rendering {
            log("Already rendering")
            return
        }
        if renderQueue.isEmpty {
            log("Nothing to render")
            return
        }
        if case .setup = PipelineState.shared.phase {
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

    private func submitToQueue(_ ids: [UUID]) {
        renderQueue.append(contentsOf: ids)
        startRenderingIfNeeded()
        save()
    }

    func createItem(basedOn prototype: ListItem, count: Int, scroll: Bool) {
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

        submitToQueue(newItems.map(\.id))
    }

    func replaceItem(basedOn prototype: ListItem) {
        guard let creatorIndex = entries.firstIndex(where: { $0.id == prototype.id }) else {
            return
        }

        let newItem = prototype.clone(as: .queued)
        withAnimation(.easeInOut(duration: 0.2)) {
            entries[creatorIndex] = newItem
        }
        submitToQueue([newItem.id])
    }

    func state(of entity: ListItem) -> ListItem.State? {
        entries.first { $0.id == entity.id }?.state
    }

    func addAndRender(entry: ListItem) async {
        await add(entry: entry)
        submitToQueue([entry.id])
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

    func createRandomVariant(of entry: ListItem) {
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
        submitToQueue(newEntries.map(\.id))
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
