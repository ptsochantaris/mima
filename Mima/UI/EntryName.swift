import SwiftUI

struct EntryName: View {
    @ObservedObject private var entry: ListItem

    init(entry: ListItem) {
        self.entry = entry
    }

    var body: some View {
        VStack {
            if entry.prompt.isEmpty && entry.negativePrompt.isEmpty {
                Text("Random prompt")
            } else if !entry.prompt.isEmpty && !entry.negativePrompt.isEmpty {
                Text(entry.prompt)
                Text("Exclude: " + entry.negativePrompt)
                    .font(.caption)
            } else {
                if !entry.prompt.isEmpty {
                    Text(entry.prompt)
                }
                if !entry.negativePrompt.isEmpty {
                    Text("Random, excluding: " + entry.negativePrompt)
                }
            }
        }
        .multilineTextAlignment(.center)
    }
}
