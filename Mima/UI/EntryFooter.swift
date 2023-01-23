import SwiftUI

struct EntryFooter: View {
    private let entry: ListItem

    init(entry: ListItem) {
        self.entry = entry
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Seed \(String(entry.seed))")
            Text("Guidance \(entry.guidance, format: .number)")
            Text("\(entry.steps, format: .number) steps")
        }
        .foregroundColor(.secondary)
        .font(.footnote)
    }
}
