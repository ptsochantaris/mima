import Foundation
import StableDiffusion
import CoreGraphics
import AsyncHTTPClient
import ZIPFoundation

enum WarmUpPhase {
    case booting, downloading(progress: Float), downloadingError(error: Error), initialising, expanding
}

@MainActor
final class PipelineState: ObservableObject {
    static let shared = PipelineState()
    
    enum Phase {
        case setup(warmupPhase: WarmUpPhase), ready(StableDiffusionPipeline), shutdown
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
            if !FileManager.default.fileExists(atPath: storageDirectory.path) {
                let temporaryZip = NSTemporaryDirectory().appending("sd15.zip")
                let tempUrl = URL(fileURLWithPath: temporaryZip)
                
                do {
                    NSLog("Requesting model...")
                    guard let client = httpClient else {
                        throw PipelineStartupError.invalidState("HTTP client setup failed")
                    }
                    let request = HTTPClientRequest(url: "https://sd-models.eu-central-1.linodeobjects.com/sd15.zip")
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
                    try FileManager.default.unzipItem(at: tempUrl, to: storageUrl)
                    NSLog("Cleaning up...")
                    try? FileManager.default.removeItem(at: tempUrl)
                    
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
            NSLog("Constructing pipeline...")
            let pipeline = try! StableDiffusionPipeline(resourcesAt: storageDirectory, disableSafety: true)
            NSLog("Warmup...")
            try? pipeline.prewarmResources()
            NSLog("Pipeline ready")
            Task { @MainActor in
                PipelineState.shared.phase = .ready(pipeline)
            }
        }
    }
    
    @MainActor
    static func render(_ item: ListItem) async {
        switch PipelineState.shared.phase {
        case .setup:
            break
        case .ready:
            item.state = .rendering(step: 0, total: Float(item.steps))
        case .shutdown:
            return
        }
        
        let result: [CGImage?] = await Task { @RenderActor in
            guard case let .ready(pipeline) = await PipelineState.shared.phase, !item.state.isCancelled else {
                return []
            }
            
            NSLog("Starting render of item \(item.id)")
            
            return try! pipeline.generateImages(
                prompt: item.prompt,
                negativePrompt: item.negativePrompt,
                imageCount: 1,
                stepCount: item.steps,
                seed: item.generatedSeed,
                guidanceScale: item.guidance,
                disableSafety: true
            ) { progress in
                return DispatchQueue.main.sync {
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
        }
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
