import Foundation
import SwiftUI

final class ListItem: ObservableObject, Codable, Identifiable {
    let id: UUID
    let prompt: String
    let negativePrompt: String
    let guidance: Float
    let seed: UInt32
    let steps: Int

    @Published var state: State

    enum CodingKeys: CodingKey {
        case prompt
        case negativePrompt
        case guidance
        case seed
        case steps
        case uuid
        case state
        case type
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .uuid)
        seed = try values.decode(UInt32.self, forKey: .seed)
        steps = try values.decode(Int.self, forKey: .steps)
        prompt = try values.decode(String.self, forKey: .prompt)
        negativePrompt = try values.decode(String.self, forKey: .negativePrompt)
        state = try values.decode(State.self, forKey: .state)
        guidance = try values.decode(Float.self, forKey: .guidance)
    }
    
    func randomVariant() -> ListItem {
        ListItem(prompt: prompt, negativePrompt: negativePrompt, seed: UInt32.random(in: 0 ..< UInt32.max), steps: steps, guidance: guidance, state: .creating)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .uuid)
        try container.encode(seed, forKey: .seed)
        try container.encode(steps, forKey: .steps)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(negativePrompt, forKey: .negativePrompt)
        try container.encode(state, forKey: .state)
        try container.encode(guidance, forKey: .guidance)
    }

    init(prompt: String, negativePrompt: String, seed: UInt32, steps: Int, guidance: Float, state: State) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.seed = seed
        self.steps = steps
        self.guidance = guidance
        self.state = state
        self.id = UUID()
    }

    func nuke() {
        state = .cancelled
        let url = imageUrl
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
    }

    var exportFilename: String {
        "\(prompt)-\(seed)-\(steps).png"
    }

    var imageUrl: URL {
        fileDirectory.appending(path: "\(id.uuidString).png")
    }

    @MainActor
    func render() async {
        switch pipelineState {
        case .warmup:
            state = .warmup
        case .ready:
            state = .rendering(step: 0, total: Float(steps))
        }

        let result = await Task.detached(priority: .userInitiated) { @RenderActor [weak self] in
            await self?.handleRender() ?? []
        }.value

        if let i = result.first, let i {
            let capturedUUID = id
            await Task.detached {
                i.save(uuid: capturedUUID)
            }.value
            state = .done
        } else {
            state = .cancelled
        }
    }

    @RenderActor
    private func handleRender() async -> [CGImage?] {
        if state.isCancelled {
            return []
        }
        guard case let .ready(pipeline) = await pipelineState else {
            return []
        }
        return try! pipeline.generateImages(
            prompt: prompt,
            negativePrompt: negativePrompt,
            imageCount: 1,
            stepCount: steps,
            seed: seed,
            guidanceScale: guidance,
            disableSafety: true
        ) { progress in
            DispatchQueue.main.sync {
                if self.state.isCancelled {
                    return false
                } else {
                    self.state = .rendering(step: Float(progress.step), total: Float(self.steps))
                    return true
                }
            }
        }
    }
}
