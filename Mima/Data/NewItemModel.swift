//
//  NewItemModel.swift
//  Mima
//
//  Created by Paul Tsochantaris on 10/02/2023.
//

import Foundation
import SwiftUI

@MainActor
final class NewItemModel: ObservableObject {
    var prototype: ListItem

    @Published var promptText = ""
    @Published var imageName = ""
    @Published var imagePath = ""
    @Published var originalImagePath = ""
    @Published var strengthText = ""
    @Published var negativePromptText = ""
    @Published var seedText = ""
    @Published var stepText = ""
    @Published var guidanceText = ""
    
    @Published var flashWhenVisible = false {
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

    func refreshFromPrototype() {
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
        let convertedStrength: Float
        if let s = Float(strengthText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            convertedStrength = s / 100.0
        } else {
            convertedStrength = ListItem.defaultStrength
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
        Task {
            try await Task.sleep(for: .milliseconds(100))
            refreshFromPrototype()
        }
    }

    func create() {
        updatePrototype()
        withAnimation(.easeInOut(duration: 0.2)) {
            Model.shared.createItem(basedOn: prototype, fromCreator: prototype.state.isCreator)
        }
        if prototype.state.isCreator {
            NotificationCenter.default.post(name: .ScrollToBottom, object: nil)
        }
    }
}