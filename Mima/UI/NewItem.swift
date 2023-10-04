import SwiftUI
import UniformTypeIdentifiers

struct NewItem: View {
    @StateObject var newItemInfo: NewItemModel

    private func go() {
        if PipelineManager.userSelectedVersion == .sdXL, Model.shared.useSafetyChecker {
            newItemInfo.showSafetyCheckerAlert = true
        } else {
            newItemInfo.create()
        }
    }

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
                                        Text(newItemInfo.imageName)
                                            .bold()
                                            .padding(EdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 0))

                                        Button {
                                            newItemInfo.imageName = ""
                                            newItemInfo.updatePrototype()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.body)
                                                .opacity(0.7)
                                        }
                                        .buttonStyle(.borderless)

                                        Spacer(minLength: 0)

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
                            go()
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
                                    go()
                                }
                            }
                        }
                        .font(.footnote)
                        .multilineTextAlignment(.center)

                        Button {
                            go()
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
        .alert("You cannot use the Stable Diffusion XL model when the safety filter is enabled, as it is currently not supported. Either use a different model or disable the safety filter.", isPresented: $newItemInfo.showSafetyCheckerAlert) {
            Button("OK", role: .cancel) {}
        }
        .overlay(alignment: .topTrailing) {
            if !newItemInfo.prototype.state.isCreator {
                MimaButon(look: .dismiss(.button))
                    .onTapGesture {
                        Model.shared.delete(newItemInfo.prototype)
                    }
            }
        }
        .overlay {
            if newItemInfo.flashWhenVisible {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.accentColor, lineWidth: 8)
            }
        }
        .onDrop(of: [.image], delegate: ImageDropDelegate(newItemInfo: newItemInfo))
        .aspectRatio(1, contentMode: .fill)
    }
}
