import SwiftUI

private struct SpinCircle: View {
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(.tint.opacity(0.4), style: StrokeStyle(lineWidth: 3.5, lineCap: .butt))
            .rotationEffect(Angle(degrees: spin ? 360 : 0))
            .animation(Animation.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
            .onAppear {
                spin = true
            }
    }
}

struct ProgressCircle: View {
    @ObservedObject var entry: ListItem
    @State private var firstUpdateAfterAppearing = true

    var body: some View {
        Group {
            switch entry.state {
            case .blocked, .cancelled, .cloning, .creating, .done, .error, .queued: Color.clear
            case let .rendering(step, total, _):
                let fraction = min(1, CGFloat(step) / CGFloat(total))
                if step < 1 {
                    SpinCircle()
                }
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .onAppear {
            firstUpdateAfterAppearing = false
        }
        .onDisappear {
            firstUpdateAfterAppearing = true
        }
    }
}
