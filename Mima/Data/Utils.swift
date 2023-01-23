import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let fileDirectory: URL = {
    let fm = FileManager.default
    let directory = fm.urls(for: .documentDirectory, in: .userDomainMask).first!.appending(path: "Mima", directoryHint: .isDirectory)
    if !fm.fileExists(atPath: directory.path, isDirectory: nil) {
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return directory
}()

extension CGImage {
    func save(uuid: UUID) {
        let url = fileDirectory.appending(path: "\(uuid.uuidString).png")
        // print("Saving to \(url.path)")
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
