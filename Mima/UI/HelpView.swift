import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            Image("help")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .background(.white)
        .frame(idealWidth: 1024, idealHeight: 1280)
    }
}

struct HelpPreviewProvider_Previews: PreviewProvider {
    static var previews: some View {
        HelpView()
    }
}
