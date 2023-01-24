import Foundation
import StableDiffusion
import CoreGraphics

private enum PipelineState {
    case warmup, ready(StableDiffusionPipeline), shutdown
}

@PipelineActor
private var pipelineState = PipelineState.warmup

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

enum Rendering {
    static func startup() {
        Task { @RenderActor in
            let url = Bundle.main.url(forResource: "sd15", withExtension: nil)!
            NSLog("Constructing pipeline...")
            let pipeline = try! StableDiffusionPipeline(resourcesAt: url, disableSafety: true)
            NSLog("Warmup...")
            try? pipeline.prewarmResources()
            NSLog("Pipeline ready")
            Task { @PipelineActor in
                pipelineState = .ready(pipeline)
            }
        }
    }
    
    @MainActor
    static func render(_ item: ListItem) async -> [CGImage?] {
        switch await pipelineState {
        case .warmup:
            item.state = .warmup
        case .ready:
            item.state = .rendering(step: 0, total: Float(item.steps))
        case .shutdown:
            return []
        }
        
        return await Task { @RenderActor in
            guard case let .ready(pipeline) = await pipelineState,
                  !item.state.isCancelled
            else {
                return []
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
    }
    
    @PipelineActor
    static func shutdown() async {
        await Model.shared.save()
        if case let .ready(pipeline) = pipelineState {
            pipelineState = .shutdown
            pipeline.unloadResources()
            NSLog("Pipeline shutdown")
        }
    }
}
