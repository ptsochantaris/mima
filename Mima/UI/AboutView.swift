//
//  AboutView.swift
//  Mima
//
//  Created by Paul Tsochantaris on 22/01/2023.
//

import SwiftUI

private let aboutText = """
There are in the mima certain features
it had come up with and which function there
in circuitry of such a kind
as human thought has never traveled through.

For example, take the third webe’s action
in the focus-works
and the ninth protator’s kinematic read-out
in the flicker phase before the screener-cell
takes over everything, allots, combines.

The inventor was himself completely dumbstruck
the day he found that one half of the mima
he’d invented lay beyond analysis.

That the mima had invented half herself.

Well, then, as everybody knows, he changed
his title, had the modesty
to realize that once she took full form
she was the superior and he himself
a secondary power, a mimator.

The mimator died, the mima stays alive.

The mimator died, the mima found her style,
progressed in comprehension of herself,
her possibilities, her limitations:
a telegrator without pride, industrious, upright,
a patient seeker, lucid and plain-dealing,
a filter of truth, with no stains of her own.

Who then can show surprise if I, the rigger
and tender of the mima on Aniara,
am moved to see how men and women, blissful
in their faith, fall on their knees to her.

And I pray too when they are at their prayer
that it be true, all this that is occurring,
and that the grace this mima is conferring
is glimpses of the light of perfect grace
that seeks us in the barren house of space.
"""

struct AboutView: View {
    var body: some View {
        ZStack {
            Color.white
            HStack {
                Image("aboutMargin")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 16)
                
                Spacer()
            }
            
            HStack(alignment: .top) {
                VStack {
                    ScrollView(showsIndicators: false) {
                        VStack {
                            VStack(spacing: 2) {
                                Text("Aniara, poem 9")
                                    .bold()
                                Text("by Harry Martinson")
                                    .bold()
                                    .font(.caption)
                            }
                            .padding(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            Text(aboutText)
                                .font(.footnote)
                        }
                        .multilineTextAlignment(.center)
                        .padding()
                        .foregroundColor(.white)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding()
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 16) {
                    Text("Mima")
                        .font(.title)
                        .bold()
                    VStack(alignment: .trailing) {
                        Text("© Copyright 2023")
                            .font(.headline)
                        Text("Paul Tsochantaris")
                            .font(.headline)
                    }
                    VStack(alignment: .trailing) {
                        Text("Mima uses Stable")
                        Text("Diffusion v1.5")
                    }
                    Text("Usage of this app and the model is subject to the Stable Diffusion license which can be found at https://raw.githubusercontent.com/CompVis/stable-diffusion/main/LICENSE")
                }
                .foregroundColor(.black.opacity(0.9))
                .padding()
                .cornerRadius(12)
                .frame(width: 256)
                .padding()
            }
            .foregroundColor(.black)
            .multilineTextAlignment(.trailing)
        }
        .frame(width: 680, height: 790)
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
