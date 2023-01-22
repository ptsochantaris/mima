#if os(macOS)
    import Cocoa
    import SwiftUI

    final class AcceptFirstMouseView: NSView {
        override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
            true
        }
    }

    struct AcceptingFirstMouse: NSViewRepresentable {
        func makeNSView(context _: NSViewRepresentableContext<AcceptingFirstMouse>) -> AcceptFirstMouseView {
            AcceptFirstMouseView()
        }

        func updateNSView(_: AcceptFirstMouseView, context _: NSViewRepresentableContext<AcceptingFirstMouse>) {
            // nsView.setNeedsDisplay(nsView.bounds)
        }

        typealias NSViewType = AcceptFirstMouseView
    }

    struct SharePicker: NSViewRepresentable {
        @Binding var isPresented: Bool
        var sharingItems: [Any]

        func makeNSView(context _: Context) -> NSView {
            AcceptFirstMouseView()
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            if isPresented {
                let picker = NSSharingServicePicker(items: sharingItems)
                picker.delegate = context.coordinator

                DispatchQueue.main.async {
                    picker.show(relativeTo: .zero, of: nsView, preferredEdge: .minY)
                }
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(owner: self)
        }

        final class Coordinator: NSObject, NSSharingServicePickerDelegate {
            let owner: SharePicker

            init(owner: SharePicker) {
                self.owner = owner
            }

            func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose _: NSSharingService?) {
                sharingServicePicker.delegate = nil
                owner.isPresented = false
            }
        }
    }
#endif
