import Combine
import Foundation
import StableDiffusion
import SwiftUI
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

@globalActor
enum RenderActor {
    final actor ActorType {}
    static let shared = ActorType()
}

extension RangeReplaceableCollection {
    mutating func popFirst() -> Element? {
        if !isEmpty {
            return removeFirst()
        }
        return nil
    }
}

enum PipelineState {
    case warmup, ready(StableDiffusionPipeline)
}

@MainActor
var pipelineState = PipelineState.warmup

func startup() {
    Task { @RenderActor in
        let url = Bundle.main.url(forResource: "sd15", withExtension: nil)!
        // NSLog("Constructing pipeline...")
        let pipeline = try! StableDiffusionPipeline(resourcesAt: url, disableSafety: true)
        // NSLog("Warmup...")
        _ = try! pipeline.generateImages(
            prompt: "",
            negativePrompt: "",
            imageCount: 1,
            stepCount: 2,
            seed: 1,
            guidanceScale: 1,
            disableSafety: true,
            progressHandler: { _ in false }
        )
        // NSLog("Done")
        Task { @MainActor in
            pipelineState = .ready(pipeline)
        }
    }
}
