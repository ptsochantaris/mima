import CoreGraphics
import CoreML
import Foundation
import StableDiffusion
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
                case .booting, .expanding, .initialising, .downloading:
                    return true
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
            
            var config = StableDiffusionPipeline.Configuration(prompt: item.prompt)
            if !item.imagePath.isEmpty, let img = NSImage(contentsOfFile: item.imagePath) {
                NSLog("Loading starting image from \(item.imagePath)")
                config.startingImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil)?.scaled(to: 512)
                config.strength = item.strength
            }
            config.negativePrompt = item.negativePrompt
            config.stepCount = item.steps
            config.seed = item.generatedSeed
            config.guidanceScale = item.guidance
            config.disableSafety = true

            return try! pipeline.generateImages(configuration: config) { progress in
                DispatchQueue.main.sync {
                    if item.state.isCancelled || item.state.isWaiting {
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
        } else {
            item.state = .error
        }
        
        return true
    }

    @MainActor
    static func shutdown() async {
        await PipelineState.shared.shutDown()
        Model.shared.save()
    }
}
