import Foundation
import SwiftUI

final class ListItem: ObservableObject, Codable, Identifiable {
    static let defaultSteps = 50
    static let defaultGuidance: Float = 7.5
    static let defaultStrength: Float = 0.6

    let id: UUID
    var prompt: String
    var negativePrompt: String
    var guidance: Float
    var seed: UInt32?
    var generatedSeed: UInt32
    var steps: Int
    var imagePath: String
    var originalImagePath: String
    var strength: Float

    @Published var imageName: String
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
        case generatedSeed
        case imagePath
        case originalImagePath
        case imageName
        case strength
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .uuid)
        seed = try values.decode(UInt32?.self, forKey: .seed)
        generatedSeed = try values.decode(UInt32.self, forKey: .generatedSeed)
        steps = try values.decode(Int.self, forKey: .steps)
        prompt = try values.decode(String.self, forKey: .prompt)
        negativePrompt = try values.decode(String.self, forKey: .negativePrompt)
        state = try values.decode(State.self, forKey: .state)
        guidance = try values.decode(Float.self, forKey: .guidance)
        imagePath = try values.decodeIfPresent(String.self, forKey: .imagePath) ?? ""
        originalImagePath = try values.decodeIfPresent(String.self, forKey: .originalImagePath) ?? ""
        imageName = try values.decodeIfPresent(String.self, forKey: .imageName) ?? ""
        strength = try values.decodeIfPresent(Float.self, forKey: .strength) ?? ListItem.defaultStrength
    }

    func randomVariant() -> ListItem {
        ListItem(prompt: prompt, imagePath: imagePath, originalImagePath: originalImagePath, imageName: imageName, strength: strength, negativePrompt: negativePrompt, seed: UInt32.random(in: 0 ..< UInt32.max), steps: steps, guidance: guidance, state: .queued)
    }

    func clone(as newState: State) -> ListItem {
        ListItem(prompt: prompt, imagePath: imagePath, originalImagePath: originalImagePath, imageName: imageName, strength: strength, negativePrompt: negativePrompt, seed: generatedSeed, steps: steps, guidance: guidance, state: newState)
    }

    func update(prompt: String, imagePath: String, originalImagePath: String, imageName: String, strength: Float, negativePrompt: String, seed: UInt32?, steps: Int, guidance: Float) {
        self.prompt = prompt
        self.imageName = imageName
        self.imagePath = imagePath
        self.originalImagePath = originalImagePath
        self.strength = max(0, min(100, strength * 100)).rounded() / 100
        self.negativePrompt = negativePrompt
        self.seed = seed
        self.steps = max(2, steps)
        self.guidance = (guidance * 1000).rounded() / 1000
        if let seed {
            generatedSeed = seed
        } else {
            generatedSeed = UInt32.random(in: 0 ..< UInt32.max)
        }
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
        try container.encode(generatedSeed, forKey: .generatedSeed)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(imageName, forKey: .imageName)
        try container.encode(strength, forKey: .strength)
        try container.encode(originalImagePath, forKey: .originalImagePath)
    }

    init(id: UUID? = nil, prompt: String, imagePath: String, originalImagePath: String, imageName: String, strength: Float, negativePrompt: String, seed: UInt32?, steps: Int, guidance: Float, state: State) {
        self.id = id ?? UUID()
        self.prompt = prompt
        self.imagePath = imagePath
        self.originalImagePath = originalImagePath
        self.imageName = imageName
        self.strength = max(0, min(1, strength))
        self.negativePrompt = negativePrompt
        self.seed = seed
        self.steps = max(2, steps)
        self.guidance = guidance
        self.state = state
        if let seed {
            generatedSeed = seed
        } else {
            generatedSeed = UInt32.random(in: 0 ..< UInt32.max)
        }
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
        "\(prompt)-\(generatedSeed)-\(steps).png"
    }

    var imageUrl: URL {
        fileDirectory.appending(path: "\(id.uuidString).png")
    }

    func copyImageToPasteboard() {
        #if canImport(Cocoa)
            guard let url = (imageUrl as NSURL).fileReferenceURL() as NSURL? else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([url])
            pb.setString(url.relativeString, forType: .fileURL)
        #elseif canImport(UIKit)
            guard let image = UIImage(contentsOfFile: imageUrl.path) else { return }
            let pb = UIPasteboard.general
            pb.image = image
        #endif
    }
}
