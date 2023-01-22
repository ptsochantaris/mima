import SwiftUI

struct EntryFooter: View {
    private let entry: GalleryEntry

    init(entry: GalleryEntry) {
        self.entry = entry
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Seed \(String(entry.seed))")
            Text("Guidance scale \(entry.guidance, format: .number)")
            Text("\(entry.steps, format: .number) steps")
        }
        .foregroundColor(.secondary)
        .font(.footnote)
    }
}
