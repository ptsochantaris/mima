import SwiftUI

struct MimaButon: View {
    enum Strength {
        case overlay, progress, button
    }

    private struct ButtonBackground: View {
        var strength: Strength
        var body: some View {
            switch strength {
            case .overlay:
                ButtonOverlayBackground()
            case .progress:
                ButtonStandardBackground()
            case .button:
                ButtonStandardBackground()
            }
        }
    }

    enum Look {
        case share, dismiss(Strength), encore, edit

        var strength: Strength {
            switch self {
            case .edit, .encore, .share:
                .overlay
            case let .dismiss(strength):
                strength
            }
        }

        var systemName: String {
            switch self {
            case .dismiss: "xmark"
            case .share: "square.and.arrow.up"
            case .encore: "arrow.clockwise"
            case .edit: "square.on.square"
            }
        }
    }

    private var look: Look

    init(look: Look) {
        self.look = look
    }

    var body: some View {
        ButtonBackground(strength: look.strength)
            .overlay {
                Image(systemName: look.systemName)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.7))
            }
        #if canImport(AppKit)
            .overlay {
                AcceptingFirstMouse()
            }
        #endif
    }
}
