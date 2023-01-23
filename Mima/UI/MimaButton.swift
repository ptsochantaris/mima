import SwiftUI

struct ButtonBackground: View {
    var body: some View {
        Group {
            if NSApp.isActive {
                Circle()
                    .foregroundStyle(.ultraThinMaterial)
            } else {
                Circle()
                    .foregroundStyle(.ultraThinMaterial.opacity(0.2))
            }
        }
        .frame(width: 26, height: 26)
        .padding(13)
    }
}

struct MimaButon: View {
    enum Look {
        case share, dismiss, encore, edit

        var systemName: String {
            switch self {
            case .dismiss: return "xmark"
            case .share: return "square.and.arrow.up"
            case .encore: return "arrow.clockwise"
            case .edit: return "square.on.square"
            }
        }
    }

    private var look: Look

    init(look: Look) {
        self.look = look
    }

    var body: some View {
        ButtonBackground()
            .overlay {
                Image(systemName: look.systemName)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.7))
            }
        #if os(macOS)
            .overlay {
                AcceptingFirstMouse()
            }
        #endif
    }
}
