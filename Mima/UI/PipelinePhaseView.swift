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

struct RetryButton: View {
    var body: some View {
        VStack(spacing: 3) {
            Icon(name: "arrow.clockwise.circle")
            Text("Retry")
                .font(.caption)
        }
        .padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        .onTapGesture {
            Task {
                PipelineBuilder.current = PipelineBuilder()
            }
        }
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
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Please wait a moment")
                        .fixedSize(horizontal: false, vertical: true)
                }
            case let .downloading(progress):
                Icon(name: "clock")
                VStack(alignment: .leading) {
                    Text("Downloading the \(PipelineBuilder.userSelectedVersion.displayName) engine. This is only needed the first time, or after an egine upgrade.")
                        .fixedSize(horizontal: false, vertical: true)
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            if progress > 0 {
                                Color.white.opacity(0.9).frame(width: proxy.size.width * CGFloat(progress))
                            }
                            Color.black.opacity(0.2)
                        }
                        .cornerRadius(3)
                        .frame(height: 6)
                    }
                }
            case .retryingDownload:
                Icon(name: "clock")
                VStack(alignment: .leading) {
                    Text("There was an issue while downloading, retrying in a moment…")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 0) {
                        Color.black.opacity(0.2)
                    }
                    .cornerRadius(3)
                    .frame(height: 6)
                }
            case let .downloadingError(error):
                RetryButton()
                VStack(alignment: .leading) {
                    Text("There was a download error!")
                        .fixedSize(horizontal: false, vertical: true)
                    Text(error.localizedDescription)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case let .initialisingError(error):
                RetryButton()
                VStack(alignment: .leading) {
                    Text("There was an error starting up the engine!")
                        .fixedSize(horizontal: false, vertical: true)
                    Text(error.localizedDescription)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .expanding:
                Icon(name: "clock")
                VStack(alignment: .leading) {
                    Text("Unpacking the engine data…")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Please wait a moment")
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .initialising:
                Icon(name: "clock")
                VStack(alignment: .leading) {
                    Text("Warming up the engine…")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("This can take a minute or more the first time!")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .foregroundColor(.white.opacity(0.9))
        .font(.callout)
        .padding()
        .background(.tint)
    }
}
