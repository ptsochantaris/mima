import CoreGraphics
import CoreML
import Foundation
import Maintini
import StableDiffusion
import SwiftUI

enum WarmUpPhase {
    case booting, downloading(progress: Float), downloadingError(error: Error), initialising, initialisingError(error: Error), expanding, retryingDownload
}

@globalActor
enum PipelineActor {
    final actor ActorType {}
    static let shared = ActorType()
}

@MainActor @Observable
final class PipelineState {
    static let shared = PipelineState()

    @MainActor
    enum Phase {
        case setup(warmupPhase: WarmUpPhase), ready(StableDiffusionPipelineProtocol), shutdown

        var showStatus: WarmUpPhase? {
            switch self {
            case .ready, .shutdown:
                nil
            case let .setup(warmupPhase):
                warmupPhase
            }
        }

        var booting: Bool {
            switch self {
            case .ready:
                false
            case .shutdown:
                true
            case let .setup(warmupPhase):
                switch warmupPhase {
                case .booting, .downloading, .expanding, .initialising, .retryingDownload: true
                case .downloadingError, .initialisingError: false
                }
            }
        }
    }

    private var phaseIsBooting = false

    private(set) var phase = Phase.setup(warmupPhase: .booting) {
        didSet {
            Task {
                let booting = phase.booting
                if phaseIsBooting != booting {
                    phaseIsBooting = booting
                    if booting {
                        Maintini.startMaintaining()
                    } else {
                        Maintini.endMaintaining()
                    }
                }
            }
        }
    }

    func setPhase(to newPhase: Phase) {
        phase = newPhase
        Task { @MainActor in
            withAnimation {
                reportedPhase = newPhase
            }
        }
    }

    @MainActor private(set) var reportedPhase = Phase.setup(warmupPhase: .booting)

    func shutDown() {
        if case let .ready(pipeline) = phase {
            setPhase(to: .shutdown)
            phase = .shutdown
            pipeline.unloadResources()
            log("Pipeline shutdown")
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

@MainActor
enum Rendering {
    static func render(_ item: ListItem) async -> Bool {
        let pipelineState = PipelineState.shared
        switch pipelineState.phase {
        case .setup:
            break
        case .ready:
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 1)) {
                    item.state = .rendering(step: -1, total: Float(item.steps), preview: nil)
                }
            }
        case .shutdown:
            return false
        }

        let result: [CGImage?] = await Task { @RenderActor in
            guard
                case let .ready(pipeline) = await pipelineState.phase,
                await (MainActor.run { item.state.isCancelled }) == false
            else {
                return []
            }

            log("Starting render of item \(item.id)")
            Task { @MainActor in
                item.state = .rendering(step: -1, total: Float(item.steps), preview: nil)
            }

            let useSafety = await Model.shared.useSafetyChecker
            let canSafetyCheck = pipeline.canSafetyCheck
            log("Using safety filter: \(useSafety && canSafetyCheck)")

            var config: PipelineConfiguration
            switch await PipelineBuilder.userSelectedVersion {
            case .sdXL:
                config = StableDiffusionXLPipeline.Configuration(prompt: item.prompt)
                config.encoderScaleFactor = 0.13025
                config.decoderScaleFactor = 0.13025
                config.decoderShiftFactor = 0
                config.schedulerTimestepShift = 1

            case .sd3m:
                config = StableDiffusion3Pipeline.Configuration(prompt: item.prompt)
                config.encoderScaleFactor = 1.5305
                config.decoderScaleFactor = 1.5305
                config.decoderShiftFactor = 0.0609
                config.schedulerTimestepShift = 3

            case .sd14, .sd15, .sd20, .sd21:
                config = StableDiffusionPipeline.Configuration(prompt: item.prompt)
                config.encoderScaleFactor = 0.18215
                config.decoderScaleFactor = 0.18215
                config.decoderShiftFactor = 0
                config.schedulerTimestepShift = 1
            }

            if !item.imagePath.isEmpty, let img = loadImage(from: URL(fileURLWithPath: item.imagePath)) {
                log("Loaded starting image from \(item.imagePath)")
                let side = await PipelineBuilder.userSelectedVersion.imageSize
                if img.width == Int(side), img.height == Int(side) {
                    config.startingImage = img
                } else {
                    config.startingImage = img.scaled(to: side) // needed if image was imported at another model resolution
                }
                config.strength = item.strength
            }
            config.negativePrompt = item.negativePrompt
            config.stepCount = item.steps
            config.seed = item.generatedSeed
            config.guidanceScale = item.guidance
            config.disableSafety = !useSafety
            config.schedulerType = .dpmSolverMultistepScheduler
            config.useDenoisedIntermediates = false

            let progressSteps: Float = if config.startingImage == nil {
                Float(item.steps)
            } else {
                (Float(item.steps) * config.strength).rounded(.down)
            }

            do {
                var lastProgressCheck = Date.distantPast
                var firstCheck = true
                let period = await Model.shared.previewGenerationInterval
                let previewGenerationPeriod = 0 - period
                let previewTransitionPeriod = max(0.1, period - 0.2)
                return try pipeline.generateImages(configuration: config) { progress in
                    if lastProgressCheck.timeIntervalSinceNow > previewGenerationPeriod {
                        return true
                    }
                    lastProgressCheck = Date.now

                    let rendering = DispatchQueue.main.sync { item.state.isRendering }
                    guard rendering else {
                        return false
                    }

                    if firstCheck {
                        firstCheck = false
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: previewTransitionPeriod)) {
                                item.state = .rendering(step: 0, total: progressSteps, preview: nil)
                            }
                        }
                        return true
                    }

                    let p = progress.currentImages.first
                    let step = Float(progress.step)
                    if let p {
                        DispatchQueue.main.sync {
                            if case .rendering = item.state {
                                withAnimation(.easeInOut(duration: previewTransitionPeriod)) {
                                    item.state = .rendering(step: step, total: progressSteps, preview: p)
                                }
                            }
                        }
                    }
                    return true
                }
            } catch {
                log("Render error: \(error.localizedDescription)")
                return await MainActor.run {
                    item.state = .error
                    return []
                }
            }
        }.value

        if let i = result.first, let i {
            withAnimation(.easeInOut(duration: 1.0)) {
                item.state = .rendering(step: 1, total: 1, preview: i)
            }
            i.save(from: item)
            withAnimation(.easeInOut(duration: 1.0)) {
                item.state = .done
            }
        } else {
            if case .error = item.state {
                log("Completed render with error")
            } else {
                item.state = .blocked
            }
        }

        return true
    }

    static func shutdown() {
        PipelineState.shared.shutDown()
        Model.shared.saveNow()
    }
}
