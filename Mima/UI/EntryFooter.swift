import SwiftUI

struct EntryFooter: View {
    private let entry: ListItem

    init(entry: ListItem) {
        self.entry = entry
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Seed \(String(entry.generatedSeed))")
            Text("Guidance \(entry.guidance, format: .number)")
            Text("\(entry.steps, format: .number) steps")
            if !entry.imagePath.isEmpty {
                Text("Mix: \(entry.strength, format: .number)")
                Text("Source Image: \(entry.imagePath)")
            }
        }
        .foregroundColor(.secondary)
        .font(.footnote)
    }
}
