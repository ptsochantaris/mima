import SwiftUI

struct GaugeProgressStyle: ProgressViewStyle {
    @State private var spin = false

    func makeBody(configuration: Configuration) -> some View {
        let fractionCompleted = configuration.fractionCompleted ?? 0

        ZStack {
            if fractionCompleted == 0 {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.tint.opacity(0.2), style: StrokeStyle(lineWidth: 3.5, lineCap: .butt))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            spin.toggle()
                        }
                    }
            }

            Circle()
                .trim(from: 0, to: fractionCompleted)
                .stroke(.tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1), value: fractionCompleted)
        }
    }
}
