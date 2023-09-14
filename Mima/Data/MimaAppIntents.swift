import AppIntents
import AppKit

enum ListItemStatus: String, AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Image status"

    static var caseDisplayRepresentations: [ListItemStatus: DisplayRepresentation] = [
        .queued: "Queued",
        .rendering: "Rendering",
        .done: "Done",
        .cancelled: "Cancelled",
        .error: "Error"
    ]

    case queued, rendering, done, cancelled, error

    init(state: ListItem.State?) {
        switch state {
        case .blocked, .cloning, .creating, .queued:
            self = .queued
        case .done:
            self = .done
        case .cancelled, .none:
            self = .cancelled
        case .error:
            self = .error
        case .rendering:
            self = .rendering
        }
    }
}

enum GladysAppIntents {
    struct MimaImageEntity: AppEntity, Identifiable {
        struct MimaImageQuery: EntityStringQuery {
            @MainActor
            func entities(matching string: String) async throws -> [MimaImageEntity] {
                Model.shared.entries
                    .filter { $0.exportFilename.contains(string) }
                    .map { MimaImageEntity(item: $0) }
            }

            @MainActor
            func entities(for identifiers: [ID]) async throws -> [MimaImageEntity] {
                identifiers
                    .compactMap { identifier in
                        Model.shared.entries.first(where: { entry in entry.id == identifier })
                    }
                    .map { MimaImageEntity(item: $0) }
            }

            @MainActor
            func suggestedEntities() async throws -> [MimaImageEntity] {
                Model.shared.entries.map { MimaImageEntity(item: $0) }
            }
        }

        static let defaultQuery = MimaImageQuery()

        var id: UUID { item.id }

        let item: ListItem

        static var typeDisplayRepresentation: TypeDisplayRepresentation { "Mima image" }

        var displayRepresentation: DisplayRepresentation {
            DisplayRepresentation(title: LocalizedStringResource(stringLiteral: item.exportFilename),
                                  subtitle: nil,
                                  image: DisplayRepresentation.Image(url: item.imageUrl))
        }
    }

    struct CreateItem: AppIntent {
        @Parameter(title: "Include")
        var include: String?

        @Parameter(title: "Exclude")
        var exclude: String?

        @Parameter(title: "Seed")
        var seed: Int?

        @Parameter(title: "Steps", default: 50)
        var steps: Int

        @Parameter(title: "Guidance", default: 7.5)
        var guidance: Double

        static var title: LocalizedStringResource { "Create a Mima image" }

        @MainActor
        func perform() async throws -> some IntentResult {
            let finalSeed = if let seed {
                UInt32(seed)
            } else {
                UInt32.random(in: 0 ..< UInt32.max)
            }

            let newItem = ListItem(prompt: include ?? "",
                                   imagePath: "",
                                   originalImagePath: "",
                                   imageName: "",
                                   strength: ListItem.defaultStrength,
                                   negativePrompt: exclude ?? "",
                                   seed: finalSeed,
                                   steps: steps,
                                   guidance: Float(guidance),
                                   state: .queued)
            await Model.shared.addAndRender(entry: newItem)
            return .result(value: MimaImageEntity(item: newItem))
        }
    }

    struct GetItemStatus: AppIntent {
        @Parameter(title: "Image")
        var image: MimaImageEntity

        static var title: LocalizedStringResource { "Get the status of an image" }

        @MainActor
        func perform() async throws -> some IntentResult {
            let status = Model.shared.state(of: image.item)
            return .result(value: ListItemStatus(state: status))
        }
    }

    struct ExportItem: AppIntent {
        @Parameter(title: "Image")
        var image: MimaImageEntity

        static var title: LocalizedStringResource { "Export an image as a file" }

        @MainActor
        func perform() async throws -> some IntentResult {
            let item = image.item
            let exportUrl = FileManager.default.temporaryDirectory.appending(path: item.exportFilename, directoryHint: .notDirectory)
            try FileManager.default.copyItem(at: item.imageUrl, to: exportUrl)
            var file = IntentFile(fileURL: item.imageUrl, filename: item.exportFilename, type: .png)
            file.removedOnCompletion = true
            return .result(value: file)
        }
    }

    struct DeleteItem: AppIntent {
        @Parameter(title: "Image")
        var image: MimaImageEntity

        static var title: LocalizedStringResource { "Delete a rendered image" }

        @MainActor
        func perform() async throws -> some IntentResult {
            Model.shared.delete(image.item)
            return .result()
        }
    }

    enum Error: Swift.Error, CustomLocalizedStringResourceConvertible {
        case error

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .error: "Failed to create image"
            }
        }
    }

    struct GladysShortcuts: AppShortcutsProvider {
        static var appShortcuts: [AppShortcut] {
            AppShortcut(intent: CreateItem(),
                        phrases: ["Create image in Mima"],
                        shortTitle: "Create image",
                        systemImageName: "wand.and.stars")

            AppShortcut(intent: GetItemStatus(),
                        phrases: ["Get Mima image status"],
                        shortTitle: "Get image status",
                        systemImageName: "doc.text.magnifyingglass")
        }
    }
}
