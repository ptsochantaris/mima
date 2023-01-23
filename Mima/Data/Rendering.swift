import Foundation
import StableDiffusion

enum PipelineState {
    case warmup, ready(StableDiffusionPipeline)
}

@globalActor
enum RenderActor {
    final actor ActorType {}
    static let shared = ActorType()
}

@RenderActor
var pipelineState = PipelineState.warmup

@RenderActor
func startup() {
    let url = Bundle.main.url(forResource: "sd15", withExtension: nil)!
    NSLog("Constructing pipeline...")
    let pipeline = try! StableDiffusionPipeline(resourcesAt: url, disableSafety: true)
    NSLog("Warmup...")
    try? pipeline.prewarmResources()
    NSLog("Pipeline ready")
    pipelineState = .ready(pipeline)
}

@RenderActor
func shutdown() async {
    await Model.shared.save()
    if case let .ready(pipeline) = pipelineState {
        pipeline.unloadResources()
        NSLog("Pipeline shutdown")
    }
}
