import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let fileDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

extension CGImage {
    func save(from item: ListItem) {
        let url = fileDirectory.appending(path: "\(item.id.uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }

        let tags: [String: String] = [
            "Prompt": item.prompt,
            "NegativePrompt": item.negativePrompt,
            "Seed": String(item.generatedSeed),
            "Steps": String(item.steps),
            "Guidance": String(item.guidance)
        ]

        let metadata = CGImageMetadataCreateMutable()
        let nameSpace = "Mima" as CFString
        let mima = "mima" as CFString
        CGImageMetadataRegisterNamespaceForPrefix(metadata, nameSpace, mima, nil)
        for kv in tags {
            let tag = CGImageMetadataTagCreate(nameSpace, mima, nameSpace, .string, kv.value as CFString)!
            CGImageMetadataSetTagWithPath(metadata, nil, "mima:\(kv.key)" as CFString, tag)
        }
        CGImageDestinationAddImageAndMetadata(destination, self, metadata, nil)
        CGImageDestinationFinalize(destination)
    }

    static func checkForEntry(from url: URL) -> ListItem? {
        if url.path.hasPrefix(NSTemporaryDirectory()) {
            NSLog("Mima to Mima drop ignored")
            return nil
        }
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        guard let metadata = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil) else {
            return nil
        }

        func getValue(for tagName: String) -> String {
            guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "mima:\(tagName)" as CFString) else {
                return ""
            }
            return CGImageMetadataTagCopyValue(tag) as? String ?? ""
        }

        return ListItem(prompt: getValue(for: "Prompt"),
                        negativePrompt: getValue(for: "NegativePrompt"),
                        seed: UInt32(getValue(for: "Seed")),
                        steps: Int(getValue(for: "Steps")) ?? ListItem.defaultSteps,
                        guidance: Float(getValue(for: "Guidance")) ?? ListItem.defaultGuidance,
                        state: .clonedCreator)
    }
}

final class ImageDropDelegate: DropDelegate {
    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.image]).first else {
            return false
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
            guard let url else {
                return
            }
            if let entry = CGImage.checkForEntry(from: url) {
                Task { @MainActor in
                    Model.shared.add(entry: entry)
                }
            }
        }
        return true
    }
}

extension RangeReplaceableCollection {
    mutating func popFirst() -> Element? {
        if !isEmpty {
            return removeFirst()
        }
        return nil
    }
}
