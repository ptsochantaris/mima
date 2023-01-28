import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let fileDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

extension CGImage {
    func save(from item: ListItem) {
        let url = fileDirectory.appending(path: "\(item.id.uuidString).png")
        if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            let metadata = CGImageMetadataCreateMutable()
            
            let tag1 = CGImageMetadataTagCreate(kCGImageMetadataNamespaceXMPBasic, nil, "Mima" as CFString, .string, item.prompt as CFString)!
            CGImageMetadataSetTagWithPath(metadata, nil, "xmp:Mima-Prompt" as CFString, tag1)

            let tag2 = CGImageMetadataTagCreate(kCGImageMetadataNamespaceXMPBasic, nil, "Mima" as CFString, .string, item.negativePrompt as CFString)!
            CGImageMetadataSetTagWithPath(metadata, nil, "xmp:Mima-Negative-Prompt" as CFString, tag2)

            let tag3 = CGImageMetadataTagCreate(kCGImageMetadataNamespaceXMPBasic, nil, "Mima" as CFString, .string, String(item.generatedSeed) as CFString)!
            CGImageMetadataSetTagWithPath(metadata, nil, "xmp:Mima-Seed" as CFString, tag3)

            let tag4 = CGImageMetadataTagCreate(kCGImageMetadataNamespaceXMPBasic, nil, "Mima" as CFString, .string, String(item.steps) as CFString)!
            CGImageMetadataSetTagWithPath(metadata, nil, "xmp:Mima-Steps" as CFString, tag4)

            let tag5 = CGImageMetadataTagCreate(kCGImageMetadataNamespaceXMPBasic, nil, "Mima" as CFString, .string, String(item.guidance) as CFString)!
            CGImageMetadataSetTagWithPath(metadata, nil, "xmp:Mima-Guidance" as CFString, tag5)

            CGImageDestinationAddImageAndMetadata(destination, self, metadata, nil)
            CGImageDestinationFinalize(destination)
        }
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
