import SwiftUI

struct NewItem: View {
    private var model: Model
    
    init(prototype: ListItem, model: Model) {
        self.model = model

        promptText = prototype.prompt

        negativePromptText = prototype.negativePrompt

        if prototype.seed == 0 {
            seedText = ""
        } else {
            seedText = String(prototype.seed)
        }
        
        if prototype.steps == 50 {
            stepText = ""
        } else {
            stepText = String(prototype.steps)
        }
        
        if prototype.guidance == 7.5 {
            guidanceText = ""
        } else {
            guidanceText = String(prototype.guidance)
        }
    }
    
    @State private var promptText: String
    @State private var negativePromptText: String
    @State private var seedText: String
    @State private var stepText: String
    @State private var guidanceText: String
    @State private var countText = ""

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.secondary.opacity(0.1)
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
                                    .frame(width: 55)
                                Text("Guidance")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 55)
                                Text("Batch Size")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 55)
                            }
                            GridRow {
                                TextField("Random", text: $seedText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                TextField("50", text: $stepText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 55)
                                TextField("7.5", text: $guidanceText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 55)
                                TextField("1", text: $countText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 55)
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
        .aspectRatio(1, contentMode: .fill)
    }
    
    @MainActor
    private func create() {
        withAnimation {
            let count = Int(countText) ?? 1
            let prototype = ListItem(prompt: promptText.trimmingCharacters(in: .whitespacesAndNewlines),
                                     negativePrompt: negativePromptText.trimmingCharacters(in: .whitespacesAndNewlines),
                                     seed: UInt32(seedText) ?? UInt32.random(in: 0 ..< UInt32.max),
                                     steps: Int(stepText) ?? 50,
                                     guidance: Float(guidanceText) ?? 7.5,
                                     state: .queued)
            model.createItems(count: count, basedOn: prototype)
        }
    }
}
