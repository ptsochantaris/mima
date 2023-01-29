import SwiftUI

struct TipView: View {
    let tip: Tip
    let tipJar: TipJar

    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(tip.image)
                    .font(.system(size: 36))
                Text(tip.priceString)
                    .font(.caption)
                    .padding(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }
            .padding(8)
        }
        .background(.ultraThinMaterial)
        .onTapGesture {
            tipJar.purchase(tip)
        }
    }
}
