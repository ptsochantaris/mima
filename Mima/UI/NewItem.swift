import SwiftUI

struct NewItem: View {
    private var prototype: ListItem

    init(prototype: ListItem) {
        self.prototype = prototype

        promptText = prototype.prompt

        negativePromptText = prototype.negativePrompt

        if let seed = prototype.seed {
            seedText = String(seed)
        } else {
            seedText = ""
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
        prototype.update(prompt: promptText.trimmingCharacters(in: .whitespacesAndNewlines),
                         negativePrompt: negativePromptText.trimmingCharacters(in: .whitespacesAndNewlines),
                         seed: UInt32(seedText),
                         steps: Int(stepText) ?? ListItem.defaultSteps,
                         guidance: Float(guidanceText) ?? ListItem.defaultGuidance)
    }

    @State private var promptText: String
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
                    VStack(alignment: .center, spacing: 30) {
                        Grid(alignment: .trailing) {
                            GridRow {
                                Text("Include")
                                    .font(.caption)
                                TextField("Random", text: $promptText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .onSubmit {
                                        create()
                                    }
                            }
                            GridRow {
                                Text("Exclude")
                                    .font(.caption)
                                TextField("", text: $negativePromptText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .onSubmit {
                                        create()
                                    }
                            }
                        }

                        Grid {
                            GridRow(alignment: .bottom) {
                                Text("Seed")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                Text("Steps")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 70)
                                Text("Guidance")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 70)
                            }
                            GridRow {
                                TextField("Random", text: $seedText)
                                TextField(String(ListItem.defaultSteps), text: $stepText)
                                    .frame(width: 70)
                                TextField(String(ListItem.defaultGuidance), text: $guidanceText)
                                    .frame(width: 70)
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .onSubmit {
                                create()
                            }
                        }

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
            }
        }
        .onChange(of: promptText) { _ in
            updatePrototype()
        }
        .onChange(of: negativePromptText) { _ in
            updatePrototype()
        }
        .onChange(of: seedText) { _ in
            updatePrototype()
        }
        .onChange(of: stepText) { _ in
            updatePrototype()
        }
        .onChange(of: guidanceText) { _ in
            updatePrototype()
        }
        .overlay(alignment: .topTrailing) {
            if !prototype.state.isCreator {
                MimaButon(look: .dismiss(.button))
                    .onTapGesture {
                        Model.shared.delete(prototype)
                    }
            }
        }
        .aspectRatio(1, contentMode: .fill)
    }

    @MainActor
    private func create() {
        updatePrototype()
        withAnimation {
            Model.shared.createItem(basedOn: prototype, fromCreator: prototype.state.isCreator)
        }
    }
}
