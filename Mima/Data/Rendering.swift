import AsyncHTTPClient
import CoreGraphics
import Foundation
import StableDiffusion
import ZIPFoundation
import SwiftUI
import CoreML

enum WarmUpPhase {
    case booting, downloading(progress: Float), downloadingError(error: Error), initialising, initialisingError(error: Error), expanding
}

@MainActor
final class PipelineState: ObservableObject {
    static let shared = PipelineState()

    enum Phase {
        case setup(warmupPhase: WarmUpPhase), ready(StableDiffusionPipeline), shutdown
        
        var showStatus: WarmUpPhase? {
            switch self {
            case .ready, .shutdown:
                return nil
            case let .setup(warmupPhase):
                return warmupPhase
            }
        }
    }

    @Published var phase = Phase.setup(warmupPhase: .booting)
}

@globalActor
enum PipelineActor {
    final actor ActorType {}
    static let shared = ActorType()
}

@globalActor
enum RenderActor {
    final actor ActorType {}
    static let shared = ActorType()
}

enum PipelineStartupError: Error {
    case invalidCode(String), invalidState(String)
}

private var httpClient: HTTPClient? = HTTPClient(eventLoopGroupProvider: .createNew)

enum Rendering {
    static func startup() {
        Task { @RenderActor in
            let storageUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let storageDirectory = storageUrl.appending(path: "sd15", directoryHint: .isDirectory)
            let checkFile = storageDirectory.appending(path: "ready", directoryHint: .notDirectory)
            if !FileManager.default.fileExists(atPath: checkFile.path) {
                #if canImport(Cocoa)
                let temporaryZip = NSTemporaryDirectory().appending("sd15.zip")
                #else
                let temporaryZip = NSTemporaryDirectory().appending("sd15iOS.zip")
                #endif
                let tempUrl = URL(fileURLWithPath: temporaryZip)

                do {
                    NSLog("Requesting model...")
                    guard let client = httpClient else {
                        throw PipelineStartupError.invalidState("HTTP client setup failed")
                    }
                    let request = HTTPClientRequest(url: "https://pub-51bef0e5d3e547d399bb6ca8d76a7d70.r2.dev/sd15.zip")
                    let response = try await client.execute(request, timeout: .seconds(120))
                    guard response.status == .ok else {
                        throw PipelineStartupError.invalidCode("Received code \(response.status) from the server")
                    }

                    NSLog("Downloading model...")
                    if FileManager.default.fileExists(atPath: temporaryZip) {
                        try FileManager.default.removeItem(at: tempUrl)
                    }
                    FileManager.default.createFile(atPath: temporaryZip, contents: nil)
                    let file = try FileHandle(forWritingTo: tempUrl)
                    let expectedBytes = response.headers.first(name: "content-length").flatMap(Int.init)
                    var receivedBytes = 0
                    for try await buffer in response.body {
                        receivedBytes += buffer.readableBytes
                        if let data = buffer.getData(at: 0, length: buffer.readableBytes) {
                            try file.write(contentsOf: data)
                        }
                        if let expectedBytes {
                            let progress = Float(receivedBytes) / Float(expectedBytes)
                            Task { @MainActor in
                                PipelineState.shared.phase = .setup(warmupPhase: .downloading(progress: progress))
                            }
                        }
                    }
                    try file.close()
                    try await client.shutdown()
                    httpClient = nil

                    Task { @MainActor in
                        PipelineState.shared.phase = .setup(warmupPhase: .expanding)
                    }

                    NSLog("Decompressing model...")
                    if FileManager.default.fileExists(atPath: storageDirectory.path) {
                        try FileManager.default.removeItem(at: storageDirectory)
                    }
                    try FileManager.default.unzipItem(at: tempUrl, to: storageUrl)
                    NSLog("Cleaning up...")
                    try FileManager.default.removeItem(at: tempUrl)
                    FileManager.default.createFile(atPath: checkFile.path, contents: nil)

                } catch {
                    Task { @MainActor in
                        PipelineState.shared.phase = .setup(warmupPhase: .downloadingError(error: error))
                    }
                    NSLog("Error setting up the model: \(error.localizedDescription)")
                    return
                }
            }

            Task { @MainActor in
                PipelineState.shared.phase = .setup(warmupPhase: .initialising)
            }

            do {
                NSLog("Constructing pipeline...")
                let config = MLModelConfiguration()
                #if canImport(Cocoa)
                config.computeUnits = .all
                let pipeline = try StableDiffusionPipeline(resourcesAt: storageDirectory, configuration: config, disableSafety: true)
                #else
                config.computeUnits = .cpuAndNeuralEngine
                let pipeline = try StableDiffusionPipeline(resourcesAt: storageDirectory, configuration: config, disableSafety: true, reduceMemory: true)
                #endif
                NSLog("Warmup...")
                try pipeline.prewarmResources()
                NSLog("Pipeline ready")
                Task { @MainActor in
                    withAnimation {
                        PipelineState.shared.phase = .ready(pipeline)
                    }
                    Model.shared.startRenderingIfNeeded()
                }
            } catch {
                Task { @MainActor in
                    PipelineState.shared.phase = .setup(warmupPhase: .initialisingError(error: error))
                }
                NSLog("Error setting up the model: \(error.localizedDescription)")
                return
            }
        }
    }

    @MainActor
    static func render(_ item: ListItem) async -> Bool {
        switch PipelineState.shared.phase {
        case .setup:
            break
        case .ready:
            item.state = .rendering(step: 0, total: Float(item.steps))
        case .shutdown:
            return false
        }

        let result: [CGImage?] = await Task { @RenderActor in
            guard case let .ready(pipeline) = await PipelineState.shared.phase, !item.state.isCancelled else {
                return []
            }

            Task { @MainActor in
                NSLog("Starting render of item \(item.id)")
                item.state = .rendering(step: 0, total: Float(item.steps))
            }

            return try! pipeline.generateImages(
                prompt: item.prompt,
                negativePrompt: item.negativePrompt,
                imageCount: 1,
                stepCount: item.steps,
                seed: item.generatedSeed,
                guidanceScale: item.guidance,
                disableSafety: true
            ) { progress in
                DispatchQueue.main.sync {
                    if item.state.isCancelled {
                        return false
                    } else {
                        item.state = .rendering(step: Float(progress.step), total: Float(item.steps))
                        return true
                    }
                }
            }
        }.value

        if let i = result.first, let i {
            let capturedUUID = item.id
            i.save(uuid: capturedUUID)
            item.state = .done
            return true
        }
        
        return false
    }

    @MainActor
    static func shutdown() async {
        Model.shared.save()
        if case let .ready(pipeline) = PipelineState.shared.phase {
            PipelineState.shared.phase = .shutdown
            pipeline.unloadResources()
            NSLog("Pipeline shutdown")
        }
    }
}
