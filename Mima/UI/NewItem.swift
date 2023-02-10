import SwiftUI
import UniformTypeIdentifiers

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
