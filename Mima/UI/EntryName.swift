import SwiftUI

struct EntryName: View {
    @ObservedObject private var entry: ListItem

    private enum Mode {
        case bothEmpty, bothFilled, positiveOnly, negativeOnly
    }

    private let mode: Mode

    private enum RenderState {
        case blocked, other, rendering
    }

    private let renderState: RenderState
    private let textAlignment: TextAlignment

    init(entry: ListItem, textAlignment: TextAlignment) {
        self.entry = entry
        let emptyPrompt = entry.prompt.isEmpty
        let emptyNegativePrompt = entry.negativePrompt.isEmpty
        if emptyPrompt, emptyNegativePrompt {
            mode = .bothEmpty
        } else if !emptyPrompt, !emptyNegativePrompt {
            mode = .bothFilled
        } else if emptyPrompt {
            mode = .negativeOnly
        } else {
            mode = .positiveOnly
        }

        switch entry.state {
        case .rendering:
            renderState = .rendering
        case .blocked:
            renderState = .blocked
        case .cancelled, .cloning, .creating, .done, .error, .queued:
            renderState = .other
        }

        self.textAlignment = textAlignment
    }

    var body: some View {
        VStack(alignment: textAlignment == .leading ? .leading : .center, spacing: 4) {
            switch mode {
            case .bothEmpty:
                Text("Random prompt")
                    .font(.headline)

            case .bothFilled:
                Text(entry.prompt)
                    .font(.headline)
                Text("Excluding: " + entry.negativePrompt)
                    .font(.caption)

            case .negativeOnly:
                Text("Random, excluding: " + entry.negativePrompt)
                    .font(.headline)

            case .positiveOnly:
                Text(entry.prompt)
                    .font(.headline)
            }

            if !entry.imagePath.isEmpty {
                Text("Cloning \(entry.imageName) at \(Int(entry.strength * 100))%")
                    .font(.caption)
            }

            if renderState == .blocked {
                Text("This image was blocked by the safety filter")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .multilineTextAlignment(textAlignment)
        .foregroundColor(renderState == .rendering ? .primary : .secondary)
    }
}
