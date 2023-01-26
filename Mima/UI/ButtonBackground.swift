//
//  ButtonBackground.swift
//  Mima
//
//  Created by Paul Tsochantaris on 26/01/2023.
//

import SwiftUI

struct ButtonOverlayBackground: View {
    var body: some View {
        Group {
            #if canImport(Cocoa)
            if NSApp.isActive {
                Circle()
                    .foregroundStyle(.ultraThinMaterial)
            } else {
                Circle()
                    .foregroundStyle(.ultraThinMaterial.opacity(0.2))
            }
            #else
            Circle()
                .foregroundStyle(.ultraThinMaterial)
            #endif
        }
        .frame(width: 26, height: 26)
        .padding(13)
    }
}

struct ButtonStandardBackground: View {
    var body: some View {
        Circle()
            .foregroundStyle(.secondary)
            .opacity(0.3)
            .frame(width: 26, height: 26)
            .padding(13)
    }
}
