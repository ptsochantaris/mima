import SwiftUI

struct Icon: View {
    var name: String
    var body: some View {
        Image(systemName: name)
            .resizable()
            .symbolVariant(.fill)
            .frame(width: 26, height: 26)
    }
}

struct PipelinePhaseView: View {
    var phase: WarmUpPhase
    
    var body: some View {
        HStack {
            switch phase {
            case .booting:
                Icon(name: "clock")
                VStack(alignment: .leading) {
                    Text("Warming up the engine…")
                    Text("Please wait a moment")
                }
            case let .downloading(progress):
                Icon(name: "clock")
                VStack(alignment: .leading) {
                    Text("Downloading the AI model files, this is only needed after the first installation…")
                        .layoutPriority(2)
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            Color.white.opacity(0.9).frame(width: proxy.size.width * CGFloat(progress))
                            Color.black.opacity(0.2)
                        }
                        .cornerRadius(3)
                        .frame(height: 6)
                    }
                }
            case let .downloadingError(error):
                Icon(name: "exclamationmark.triangle")
                VStack(alignment: .leading) {
                    Text("There was a download error!")
                    Text(error.localizedDescription)
                }
            case let .initialisingError(error):
                Icon(name: "exclamationmark.triangle")
                VStack(alignment: .leading) {
                    Text("There was an error starting up the AI model!")
                    Text(error.localizedDescription)
                }
            case .expanding:
                Icon(name: "clock")
                VStack(alignment: .leading) {
                    Text("Expanding the AI model data…")
                    Text("Please wait a moment")
                }
            case .initialising:
                Icon(name: "clock")
                VStack(alignment: .leading) {
                    Text("Warming up the engine…")
                    Text("This can take a few minutes or more the first time!")
                }
            }
            
            Spacer()
        }
        .foregroundColor(.white.opacity(0.9))
        .font(.callout)
        .padding()
        .background(.tint.opacity(0.7))
    }
}
