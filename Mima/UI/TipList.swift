import SwiftUI

struct TipList: View {
    private let jar = TipJar()
    var body: some View {
        VStack(alignment: .trailing) {
            switch jar.state {
            case .busy:
                Text("If you enjoy using this app, please consider leavng a tip, it would be greatly appreciated!")
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .frame(height: 74)

            case .ready:
                Text("If you enjoy using this app, please consider leavng a tip, it would be greatly appreciated!")
                HStack(spacing: 2) {
                    TipView(tip: jar.tip1, tipJar: jar)
                    TipView(tip: jar.tip2, tipJar: jar)
                    TipView(tip: jar.tip3, tipJar: jar)
                }
                .cornerRadius(15)

            case .success:
                Text("Thank you for supporting Mima!")
                    .multilineTextAlignment(.center)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(.green)
                    .cornerRadius(15)

            case let .error(error):
                Text("There was an error: \(error.localizedDescription)")
                    .multilineTextAlignment(.center)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(.red)
                    .onTapGesture {
                        jar.state = .ready
                    }
                    .cornerRadius(15)
            }
        }
    }
}
