import SwiftUI

struct EntryName: View {
    @ObservedObject private var entry: ListItem

    init(entry: ListItem) {
        self.entry = entry
    }

    var body: some View {
        VStack(spacing: 4) {
            if entry.prompt.isEmpty, entry.negativePrompt.isEmpty {
                Text("Random prompt")
                    .font(.headline)

            } else if !entry.prompt.isEmpty, !entry.negativePrompt.isEmpty {
                Text(entry.prompt)
                Text("Excluding: " + entry.negativePrompt)
                    .font(.caption)
            } else {
                if !entry.prompt.isEmpty {
                    Text(entry.prompt)
                        .font(.headline)
                }
                if !entry.negativePrompt.isEmpty {
                    Text("Random, excluding: " + entry.negativePrompt)
                        .font(.headline)
                }
            }

            if !entry.imagePath.isEmpty {
                Text("Cloning \(entry.imageName) at \(Int(entry.strength * 100))%")
                    .font(.caption)
            }

        }
        .multilineTextAlignment(.center)
    }
}
