import SwiftUI

struct EntryName: View {
    @ObservedObject private var entry: GalleryEntry

    init(entry: GalleryEntry) {
        self.entry = entry
    }

    var body: some View {
        Group {
            if entry.negativePrompt.isEmpty {
                Text(entry.prompt)
            } else {
                Text("+ " + entry.prompt)
                Text("- " + entry.negativePrompt)
            }
        }
        .multilineTextAlignment(.center)
    }
}
