import SwiftUI

struct ButtonOverlayBackground: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Circle()
            .foregroundStyle(.ultraThinMaterial.opacity(scenePhase == .active ? 1 : 0.2))
            .frame(width: 26, height: 26)
            .padding(13)
    }
}

struct ButtonStandardBackground: View {
    var body: some View {
        Circle()
            .foregroundStyle(.secondary)
            .opacity(0.3)
            .frame(width: 26, height: 26)
            .padding(13)
    }
}
