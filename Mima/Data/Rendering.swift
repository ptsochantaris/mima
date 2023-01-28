import CoreGraphics
import Foundation
import StableDiffusion
import ZIPFoundation
import SwiftUI
import CoreML

enum WarmUpPhase {
    case booting, downloading(progress: Float), downloadingError(error: Error), initialising, initialisingError(error: Error), expanding
}

@globalActor
enum PipelineActor {
    final actor ActorType {}
    static let shared = ActorType()
}

@PipelineActor
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
    
    var phase = Phase.setup(warmupPhase: .booting) {
        didSet {
            let p = phase
            Task { @MainActor in
                reportedPhase = p
            }
        }
    }
    
    @MainActor @Published var reportedPhase = Phase.setup(warmupPhase: .booting)
    
    func shutDown() {
        if case let .ready(pipeline) = phase {
            phase = .shutdown
            pipeline.unloadResources()
            NSLog("Pipeline shutdown")
        }
    }
}

@globalActor
enum RenderActor {
    final actor ActorType {}
    static let shared = ActorType()
}

enum PipelineStartupError: Error {
    case invalidCode(String), invalidState(String)
}

enum FetchError: Error {
    case noDataDownloaded(String)
}

enum Rendering {
    @MainActor
    static func render(_ item: ListItem) async -> Bool {
        switch await PipelineState.shared.phase {
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
            i.save(from: item)
            item.state = .done
            return true
        }
        
        return false
    }

    @MainActor
    static func shutdown() async {
        await PipelineState.shared.shutDown()
        Model.shared.save()
    }
}
