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
            "Guidance": String(item.guidance),
            "I2IPath": String(item.imagePath),
            "I2IName": String(item.imageName),
            "I2IStrength": String(item.strength)
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

        var notFoundCount = 0
        func getValue(for tagName: String) -> String {
            guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "mima:\(tagName)" as CFString) else {
                notFoundCount += 1
                return ""
            }
            return CGImageMetadataTagCopyValue(tag) as? String ?? ""
        }
                
        let item = ListItem(prompt: getValue(for: "Prompt"),
                            imagePath: "",
                            originalImagePath: getValue(for: "I2IPath"),
                            imageName: getValue(for: "I2IName"),
                            strength: Float(getValue(for: "I2IStrength")) ?? ListItem.defaultStrength,
                            negativePrompt: getValue(for: "NegativePrompt"),
                            seed: UInt32(getValue(for: "Seed")),
                            steps: Int(getValue(for: "Steps")) ?? ListItem.defaultSteps,
                            guidance: Float(getValue(for: "Guidance")) ?? ListItem.defaultGuidance,
                            state: .clonedCreator)
        
        if notFoundCount == 8 {
            item.originalImagePath = url.path
        }
        
        if !item.originalImagePath.isEmpty {
            item.imageName = url.lastPathComponent
            item.imagePath = Model.shared.ingestCloningAsset(from: URL(filePath: item.originalImagePath))
        }

        return item
    }
}

final class ImageDropDelegate: DropDelegate {
    private let newItemInfo: NewItemModel?
    init(newItemInfo: NewItemModel? = nil) {
        self.newItemInfo = newItemInfo
    }
    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.url]).first else {
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            if let error {
                NSLog("Drop error: \(error)")
                return
            }
            guard let url else {
                NSLog("Drop error - no URL or error")
                return
            }
            if let info = self.newItemInfo {
                Task { @MainActor in
                    info.originalImagePath = url.path
                    info.imageName = url.lastPathComponent
                    info.imagePath = Model.shared.ingestCloningAsset(from: url)
                    info.updatePrototype()
                }
            } else if let entry = CGImage.checkForEntry(from: url) {
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
