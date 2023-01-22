import SwiftUI

struct NewItem: View {
    @ObservedObject private var model: Model

    init(model: Model) {
        self.model = model
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.secondary.opacity(0.3)
                HStack {
                    Spacer()
                    VStack(alignment: .center, spacing: 30) {
                        Grid(alignment: .trailing) {
                            GridRow {
                                Text("Include")
                                    .font(.caption)
                                TextField("Mima Bird", text: $model.prompt)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .onSubmit {
                                        withAnimation {
                                            model.createItems()
                                        }
                                    }
                            }
                            GridRow {
                                Text("Exclude")
                                    .font(.caption)
                                TextField("", text: $model.negativePrompt)
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
                                Text("Guidance Scale")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 55)
                                Text("Batch Size")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 55)
                            }
                            GridRow {
                                TextField("Random", text: $model.seed)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                TextField("50", text: $model.steps)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 55)
                                TextField("7.5", text: $model.guidance)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 55)
                                TextField("1", text: $model.count)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 55)
                            }
                        }

                        Button {
                            withAnimation {
                                model.createItems()
                            }
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
}
