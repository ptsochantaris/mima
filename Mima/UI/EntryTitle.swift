import SwiftUI

struct EntryTitle: View {
    @ObservedObject private var entry: ListItem

    init(entry: ListItem) {
        self.entry = entry
    }

    var body: some View {
        VStack(spacing: 8) {
            if case .rendering = entry.state {
                EntryName(entry: entry)
                    .foregroundColor(.primary)
            } else {
                EntryName(entry: entry)
                    .foregroundColor(.secondary)
            }
            Spacer()
                .frame(height: 1)
        }
        .font(.headline)
        .padding(EdgeInsets(top: 0, leading: 50, bottom: 0, trailing: 50))
    }
}
