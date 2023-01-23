import SwiftUI

struct GaugeProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fractionCompleted = configuration.fractionCompleted ?? 0

        Circle()
            .trim(from: 0, to: fractionCompleted)
            .stroke(.tint, style: StrokeStyle(lineWidth: 5, lineCap: .butt))
            .rotationEffect(.degrees(-90))
    }
}
