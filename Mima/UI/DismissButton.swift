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
        case .cancelled, .cloning, .creating, .error, .queued, .blocked:
            MimaButon(look: .dismiss(.button))
                .onTapGesture {
                    withAnimation {
                        Model.shared.delete(entry)
                    }
                }

        case .rendering:
            ZStack {
                MimaButon(look: .dismiss(.progress))
                    .onTapGesture {
                        withAnimation {
                            Model.shared.delete(entry)
                        }
                    }
                    .overlay {
                        ProgressCircle(entry: entry)
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
