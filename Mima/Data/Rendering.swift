import CoreGraphics
import CoreML
import Foundation
@preconcurrency import StableDiffusion
import SwiftUI
import ZIPFoundation

#if canImport(Cocoa)
typealias IMAGE = NSImage

extension NSImage {
    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

#else
typealias IMAGE = UIImage
#endif

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

extension CGImage {
    func scaled(to sideLength: CGFloat) -> CGImage? {
        let scaledImageSize: CGSize
        let W = CGFloat(width)
        let H = CGFloat(height)
        if width < height {
            let lateralScale = sideLength / W
            scaledImageSize = CGSize(width: sideLength, height: H * lateralScale)
        } else {
            let verticalScale = sideLength / H
            scaledImageSize = CGSize(width: W * verticalScale, height: sideLength)
        }

        let c = CGContext(data: nil,
                          width: Int(sideLength),
                          height: Int(sideLength),
                          bitsPerComponent: 8,
                          bytesPerRow: Int(sideLength) * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)!
        c.interpolationQuality = .high

        let scaledImageRect = CGRect(x: (sideLength - scaledImageSize.width) * 0.5,
                                     y: (sideLength - scaledImageSize.height) * 0.5,
                                     width: scaledImageSize.width,
                                     height: scaledImageSize.height)

        c.draw(self, in: scaledImageRect)
        return c.makeImage()
    }
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
            if !item.imagePath.isEmpty, let img = IMAGE(contentsOfFile: item.imagePath) {
                log("Loading starting image from \(item.imagePath)")
                config.startingImage = img.cgImage?.scaled(to: 512)
                config.strength = item.strength
            }
            config.negativePrompt = item.negativePrompt
            config.stepCount = item.steps
            config.seed = item.generatedSeed
            config.guidanceScale = item.guidance
            config.disableSafety = !useSafety

            do {
                return try pipeline.generateImages(configuration: config) { progress in
                    DispatchQueue.main.sync {
                        if item.state.isCancelled || item.state.isWaiting {
                            return false
                        } else {
                            item.state = .rendering(step: Float(progress.step), total: Float(item.steps))
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
