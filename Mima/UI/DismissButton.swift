import SwiftUI

struct DismissButton: View {
    @ObservedObject private var entry: ListItem
    private let visibleControls: Bool

    init(entry: ListItem, visibleControls: Bool) {
        self.entry = entry
        self.visibleControls = visibleControls
    }

    var body: some View {
        switch entry.state {
        case .cancelled, .clonedCreator, .creating, .error, .queued:
            MimaButon(look: .dismiss(.button))
                .onTapGesture {
                    withAnimation {
                        Model.shared.delete(entry)
                    }
                }

        case let .rendering(step, total):
            ZStack {
                MimaButon(look: .dismiss(.progress))
                    .onTapGesture {
                        withAnimation {
                            Model.shared.delete(entry)
                        }
                    }
                    .overlay {
                        ProgressView(value: step, total: total)
                            .progressViewStyle(GaugeProgressStyle())
                            .frame(width: 29, height: 29)
                    }
            }

        case .done:
            if visibleControls {
                MimaButon(look: .dismiss(.overlay))
                    .onTapGesture {
                        withAnimation {
                            Model.shared.delete(entry)
                        }
                    }
            }
        }
    }
}