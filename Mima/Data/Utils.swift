import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let fileDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

extension CGImage {
    func save(uuid: UUID) {
        let url = fileDirectory.appending(path: "\(uuid.uuidString).png")
        if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, self, nil)
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
