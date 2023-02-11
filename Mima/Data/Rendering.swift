import CoreGraphics
import CoreML
import Foundation
@preconcurrency import StableDiffusion
import SwiftUI
import ZIPFoundation

enum WarmUpPhase {
    case booting, downloading(progress: Float), downloadingError(error: Error), initialising, initialisingError(error: Error), expanding
}

@globalActor
enum PipelineActor {
    final actor ActorType {}
    static let shared = ActorType()
}

final actor PipelineState: ObservableObject {
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

        var booting: Bool {
            switch self {
            case .ready:
                return false
            case .shutdown:
                return true
            case let .setup(warmupPhase):
                switch warmupPhase {
                case .booting, .downloading, .expanding, .initialising:  return true
                case .downloadingError, .initialisingError:
                    return false
                }
            }
        }
    }

    private(set) var phase = Phase.setup(warmupPhase: .booting)

    func setPhase(to newPhase: Phase) {
        phase = newPhase
        Task { @MainActor in
            withAnimation {
                reportedPhase = newPhase
            }
        }
    }

    @MainActor @Published private(set) var reportedPhase = Phase.setup(warmupPhase: .booting)

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

enum Rendering {
    @MainActor
    static func render(_ item: ListItem) async -> Bool {
        switch await PipelineState.shared.phase {
        case .setup:
            break
        case .ready:
            Task { @MainActor in
                item.state = .rendering(step: 0, total: Float(item.steps))
            }
        case .shutdown:
            return false
        }

        let result: [CGImage?] = await Task { @RenderActor in
            guard
                case let .ready(pipeline) = await PipelineState.shared.phase,
                (await MainActor.run { item.state.isCancelled }) == false
            else {
                return []
            }

            log("Starting render of item \(item.id)")
            Task { @MainActor in
                item.state = .rendering(step: 0, total: Float(item.steps))
            }
            
            let useSafety = await Model.shared.useSafetyChecker
            log("Using safety filter: \(useSafety && pipeline.canSafetyCheck)")

            var config = StableDiffusionPipeline.Configuration(prompt: item.prompt)
            if !item.imagePath.isEmpty, let img = loadImage(from: URL(fileURLWithPath: item.imagePath)) {
                log("Loaded starting image from \(item.imagePath)")
                if img.width == 512 && img.height == 512 {
                    config.startingImage = img
                } else {
                    config.startingImage = img.scaled(to: 512) // remove eventually
                }
                config.strength = item.strength
            }
            config.negativePrompt = item.negativePrompt
            config.stepCount = item.steps
            config.seed = item.generatedSeed
            config.guidanceScale = item.guidance
            config.disableSafety = !useSafety
            
            let progressSteps: Float
            if config.startingImage == nil {
                progressSteps = Float(item.steps)
            } else {
                progressSteps = (Float(item.steps) * config.strength).rounded(.down)
            }

            do {
                return try pipeline.generateImages(configuration: config) { progress in
                    DispatchQueue.main.sync {
                        if item.state.isCancelled || item.state.isWaiting {
                            return false
                        } else {
                            item.state = .rendering(step: Float(progress.step), total: progressSteps)
                            return true
                        }
                    }
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
            i.save(from: item)
            item.state = .done
        } else {
            if case .error = item.state {
                log("Completed render with error")
            } else {
                item.state = .blocked
            }
        }

        return true
    }

    @MainActor
    static func shutdown() async {
        await PipelineState.shared.shutDown()
        Model.shared.save()
    }
}
