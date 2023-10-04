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

final actor PipelineState: ObservableObject {
    static let shared = PipelineState()

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
            let booting = phase.booting
            if phaseIsBooting != booting {
                phaseIsBooting = booting
                if booting {
                    Task { @MainActor in
                        Maintini.startMaintaining()
                    }
                } else {
                    Task { @MainActor in
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
                withAnimation(.easeInOut(duration: 1)) {
                    item.state = .rendering(step: -1, total: Float(item.steps), preview: nil)
                }
            }
        case .shutdown:
            return false
        }

        let result: [CGImage?] = await Task { @RenderActor in
            guard
                case let .ready(pipeline) = await PipelineState.shared.phase,
                await (MainActor.run { item.state.isCancelled }) == false
            else {
                return []
            }

            log("Starting render of item \(item.id)")
            Task { @MainActor in
                item.state = .rendering(step: -1, total: Float(item.steps), preview: nil)
            }

            let useSafety = await Model.shared.useSafetyChecker
            log("Using safety filter: \(useSafety && pipeline.canSafetyCheck)")

            var config: PipelineConfiguration = if #available(macOS 14.0, *), PipelineManager.userSelectedVersion == .sdXL {
                StableDiffusionXLPipeline.Configuration(prompt: item.prompt)
            } else {
                StableDiffusionPipeline.Configuration(prompt: item.prompt)
            }
            if !item.imagePath.isEmpty, let img = loadImage(from: URL(fileURLWithPath: item.imagePath)) {
                log("Loaded starting image from \(item.imagePath)")
                let side = PipelineManager.userSelectedVersion.imageSize
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
                return try pipeline.generateImages(configuration: config) { progress in
                    if lastProgressCheck.timeIntervalSinceNow > -2 {
                        return true
                    }
                    lastProgressCheck = Date.now
                    return DispatchQueue.main.sync {
                        if item.state.isCancelled || item.state.isWaiting {
                            return false
                        }
                        if firstCheck {
                            firstCheck = false
                            DispatchQueue.main.async {
                                if case .rendering = item.state {
                                    withAnimation(.easeInOut(duration: 1.5)) {
                                        item.state = .rendering(step: 0, total: progressSteps, preview: nil)
                                    }
                                }
                            }

                        } else {
                            DispatchQueue.global(qos: .background).async {
                                if let p = progress.currentImages.first, let p {
                                    let step = Float(progress.step)
                                    DispatchQueue.main.async {
                                        if case .rendering = item.state {
                                            withAnimation(.easeInOut(duration: 1.5)) {
                                                item.state = .rendering(step: step, total: progressSteps, preview: p)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        return true
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

    @MainActor
    static func shutdown() async {
        await PipelineState.shared.shutDown()
        Model.shared.saveNow()
    }
}
