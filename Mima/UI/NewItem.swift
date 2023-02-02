import SwiftUI
import UniformTypeIdentifiers

struct NewItem: View {
    private var prototype: ListItem

    init(prototype: ListItem) {
        self.prototype = prototype

        promptText = prototype.prompt
                
        imagePath = prototype.imagePath

        negativePromptText = prototype.negativePrompt

        if let seed = prototype.seed {
            seedText = String(seed)
        } else {
            seedText = ""
        }

        if prototype.strength == ListItem.defaultStrength {
            strengthText = ""
        } else {
            strengthText = String(prototype.strength * 100)
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

    private func updatePrototype() {
        let convertedStrength: Float
        if let s = Float(strengthText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            convertedStrength = s / 100.0
        } else {
            convertedStrength = ListItem.defaultStrength
        }
        prototype.update(prompt: promptText.trimmingCharacters(in: .whitespacesAndNewlines),
                         imagePath: imagePath.trimmingCharacters(in: .whitespacesAndNewlines),
                         strength: convertedStrength,
                         negativePrompt: negativePromptText.trimmingCharacters(in: .whitespacesAndNewlines),
                         seed: UInt32(seedText.trimmingCharacters(in: .whitespacesAndNewlines)),
                         steps: Int(stepText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ListItem.defaultSteps,
                         guidance: Float(guidanceText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ListItem.defaultGuidance)
    }

    @State private var promptText: String
    @State private var imagePath: String
    @State private var strengthText: String
    @State private var negativePromptText: String
    @State private var seedText: String
    @State private var stepText: String
    @State private var guidanceText: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ItemBackground()
                HStack {
                    Spacer()
                    VStack(alignment: .center, spacing: 20) {
                        Grid(alignment: .trailing) {
                            GridRow {
                                Text("Include")
                                    .font(.caption)
                                TextField("Random", text: $promptText, onEditingChanged: { editing in
                                    if !editing {
                                        updatePrototype()
                                    }
                                })
                                .font(.caption)
                                .onSubmit {
                                    create()
                                }
                            }
                            GridRow {
                                Text("Exclude")
                                    .font(.caption)
                                TextField("", text: $negativePromptText, onEditingChanged: { editing in
                                    if !editing {
                                        updatePrototype()
                                    }
                                })
                                .font(.caption)
                                .onSubmit {
                                    create()
                                }
                            }
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
                                    TextField("Random", text: $seedText, onEditingChanged: { editing in
                                        if !editing {
                                            updatePrototype()
                                        }
                                    })
                                    TextField(String(ListItem.defaultSteps), text: $stepText, onEditingChanged: { editing in
                                        if !editing {
                                            updatePrototype()
                                        }
                                    })
                                    .frame(width: 70)
                                    TextField(String(ListItem.defaultGuidance), text: $guidanceText, onEditingChanged: { editing in
                                        if !editing {
                                            updatePrototype()
                                        }
                                    })
                                    .frame(width: 70)
                                }
                                .onSubmit {
                                    create()
                                }
                            }
                            
                            if !imagePath.isEmpty {
                                Grid {
                                    GridRow {
                                        TextField("No Source Image", text: $imagePath, onEditingChanged: { editing in
                                            if !editing {
                                                updatePrototype()
                                            }
                                        })
                                        TextField(String(ListItem.defaultStrength * 100), text: $strengthText, onEditingChanged: { editing in
                                            if !editing {
                                                updatePrototype()
                                            }
                                        })
                                        .frame(width: 70)
                                    }
                                    .onSubmit {
                                        create()
                                    }
                                    GridRow(alignment: .bottom) {
                                        Text("Source Image")
                                            .font(.caption)
                                        Text("Mix %")
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        .font(.footnote)
                        .multilineTextAlignment(.center)

                        Button {
                            create()
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
            if !prototype.state.isCreator {
                MimaButon(look: .dismiss(.button))
                    .onTapGesture {
                        Model.shared.delete(prototype)
                    }
            }
        }
        .onDrop(of: [.image], delegate: CreatorDropDelegate(prototype: prototype))
        .aspectRatio(1, contentMode: .fill)
    }
    
    private final class CreatorDropDelegate: DropDelegate {
        let prototype: ListItem
        init(prototype: ListItem) {
            self.prototype = prototype
        }
        func performDrop(info: DropInfo) -> Bool {
            guard let provider = info.itemProviders(for: [.image]).first else {
                return false
            }
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _, _ in
                if let self, let path = url?.path {
                    Task { @MainActor in
                        self.prototype.imagePath = path
                        self.prototype.objectWillChange.send()
                    }
                }
            }
            return true
        }
    }

    @MainActor
    private func create() {
        updatePrototype()
        withAnimation {
            Model.shared.createItem(basedOn: prototype, fromCreator: prototype.state.isCreator)
        }
    }
}
