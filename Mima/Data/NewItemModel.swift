import Foundation
import SwiftUI

@MainActor @Observable
final class NewItemModel {
    var prototype: ListItem

    var showSafetyCheckerAlert = false
    var promptText = ""
    var imageName = ""
    var imagePath = ""
    var originalImagePath = ""
    var strengthText = ""
    var negativePromptText = ""
    var seedText = ""
    var stepText = ""
    var guidanceText = ""

    var flashWhenVisible = false {
        didSet {
            if flashWhenVisible {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation {
                        flashWhenVisible = false
                    }
                }
            }
        }
    }

    init(prototype: ListItem) {
        self.prototype = prototype
        refreshFromPrototype()
        if case let .cloning(flash) = prototype.state {
            flashWhenVisible = flash
        }
    }

    private func refreshFromPrototype() {
        log("Loading latest prototype data")
        promptText = prototype.prompt

        imageName = prototype.imageName
        imagePath = prototype.imagePath
        originalImagePath = prototype.originalImagePath
        negativePromptText = prototype.negativePrompt

        if let seed = prototype.seed {
            seedText = String(seed)
        } else {
            seedText = ""
        }

        if prototype.strength == ListItem.defaultStrength {
            strengthText = ""
        } else {
            strengthText = String(Int(prototype.strength * 100))
        }

        if prototype.steps == ListItem.defaultSteps {
            stepText = ""
        } else {
            stepText = String(prototype.steps)
        }

        if prototype.guidance == ListItem.defaultGuidance {
            guidanceText = ""
        } else {
            guidanceText = String(prototype.guidance)
        }
    }

    func updatePrototype() {
        let convertedStrength: Float = if let s = Float(strengthText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            s / 100.0
        } else {
            ListItem.defaultStrength
        }
        let imageName = imageName.trimmingCharacters(in: .whitespacesAndNewlines)
        prototype.update(prompt: promptText.trimmingCharacters(in: .whitespacesAndNewlines),
                         imagePath: imageName.isEmpty ? "" : imagePath,
                         originalImagePath: imageName.isEmpty ? "" : originalImagePath,
                         imageName: imageName,
                         strength: convertedStrength,
                         negativePrompt: negativePromptText.trimmingCharacters(in: .whitespacesAndNewlines),
                         seed: UInt32(seedText.trimmingCharacters(in: .whitespacesAndNewlines)),
                         steps: Int(stepText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ListItem.defaultSteps,
                         guidance: Float(guidanceText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ListItem.defaultGuidance)
        refreshFromPrototype()
    }

    func create() {
        if prototype.state.isCreator {
            #if canImport(AppKit)
                let optionClick = NSEvent.modifierFlags.contains(.option)
                let count = optionClick ? Model.shared.optionClickRepetitions : 1
            #else
                let optionClick = false
                let count = 1
            #endif
            prototype.willClone = { [weak self] in
                self?.updatePrototype()
            }
            Model.shared.createItem(basedOn: prototype, count: count, scroll: !optionClick)
            prototype.willClone = nil

        } else {
            Model.shared.replaceItem(basedOn: prototype)
        }
    }
}
