import SwiftUI

struct GaugeProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fractionCompleted = configuration.fractionCompleted ?? 0

        ZStack {
            if fractionCompleted == 0 {
                Circle()
                    .stroke(.tint.opacity(0.3), style: StrokeStyle(lineWidth: 3.5, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }

            Circle()
                .trim(from: 0, to: fractionCompleted)
                .stroke(.tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
    }
}
