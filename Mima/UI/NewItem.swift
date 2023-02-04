import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class NewItemModel: ObservableObject {
    var prototype: ListItem

    @Published var promptText: String = ""
    @Published var imageName: String = ""
    @Published var imagePath: String = ""
    @Published var originalImagePath: String = ""
    @Published var strengthText: String = ""
    @Published var negativePromptText: String = ""
    @Published var seedText: String = ""
    @Published var stepText: String = ""
    @Published var guidanceText: String = ""

    init(prototype: ListItem) {
        self.prototype = prototype
        refreshFromPrototype()
    }
    
    func refreshFromPrototype() {
        NSLog("Loading latest prototype data")
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
        withAnimation {
            Model.shared.createItem(basedOn: prototype, fromCreator: prototype.state.isCreator)
        }
    }
}

struct NewItem: View {
    @StateObject var newItemInfo: NewItemModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ItemBackground()
                HStack {
                    Spacer()
                    VStack(alignment: .center, spacing: 20) {
                        Grid(alignment: .trailing) {
                            if !newItemInfo.imageName.isEmpty {
                                GridRow {
                                    Text("Clone")
                                    HStack(spacing: 4) {
                                        TextField("No Source Image", text: $newItemInfo.imageName, onEditingChanged: { editing in
                                            if !editing {
                                                newItemInfo.updatePrototype()
                                            }
                                        })
                                        Text("at")
                                        TextField(String(Int(ListItem.defaultStrength * 100)) + "%", text: $newItemInfo.strengthText, onEditingChanged: { editing in
                                            if !editing {
                                                newItemInfo.updatePrototype()
                                            }
                                        })
                                        .multilineTextAlignment(.center)
                                        .frame(width: 50)
                                    }
                                }
                            }
                            GridRow {
                                Text("Include")
                                TextField("Random", text: $newItemInfo.promptText, onEditingChanged: { editing in
                                    if !editing {
                                        newItemInfo.updatePrototype()
                                    }
                                })
                            }
                            GridRow {
                                Text("Exclude")
                                TextField("", text: $newItemInfo.negativePromptText, onEditingChanged: { editing in
                                    if !editing {
                                        newItemInfo.updatePrototype()
                                    }
                                })
                            }
                        }
                        .font(.caption)
                        .onSubmit {
                            newItemInfo.create()
                        }

                        VStack {
                            Grid {
                                GridRow(alignment: .bottom) {
                                    Text("Seed")
                                        .font(.caption)
                                    Text("Steps")
                                        .font(.caption)
                                        .frame(width: 70)
                                    Text("Guidance")
                                        .font(.caption)
                                        .frame(width: 70)
                                }
                                GridRow {
                                    TextField("Random", text: $newItemInfo.seedText, onEditingChanged: { editing in
                                        if !editing {
                                            newItemInfo.updatePrototype()
                                        }
                                    })
                                    TextField(String(ListItem.defaultSteps), text: $newItemInfo.stepText, onEditingChanged: { editing in
                                        if !editing {
                                            newItemInfo.updatePrototype()
                                        }
                                    })
                                    .frame(width: 70)
                                    TextField(String(ListItem.defaultGuidance), text: $newItemInfo.guidanceText, onEditingChanged: { editing in
                                        if !editing {
                                            newItemInfo.updatePrototype()
                                        }
                                    })
                                    .frame(width: 70)
                                }
                                .onSubmit {
                                    newItemInfo.create()
                                }
                            }
                        }
                        .font(.footnote)
                        .multilineTextAlignment(.center)

                        Button {
                            newItemInfo.create()
                        } label: {
                            Text("Create")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(width: 100 + proxy.size.width * 0.6)
                    Spacer()
                }
                .textFieldStyle(.roundedBorder)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !newItemInfo.prototype.state.isCreator {
                MimaButon(look: .dismiss(.button))
                    .onTapGesture {
                        Model.shared.delete(newItemInfo.prototype)
                    }
            }
        }
        .onDrop(of: [.image], delegate: ImageDropDelegate(newItemInfo: newItemInfo))
        .aspectRatio(1, contentMode: .fill)
    }
}
