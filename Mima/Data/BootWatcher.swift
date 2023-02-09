import Combine
import Foundation
import SwiftUI

@MainActor
final class BootWatcher: ObservableObject {
    @ObservedObject private var pipeline = PipelineState.shared
    private var observer: Cancellable?

    @Published var booting = PipelineState.shared.reportedPhase.booting

    init() {
        observer = pipeline.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] in
            guard let self else { return }
            let phase = self.pipeline.reportedPhase.booting
            if phase != self.booting {
                self.booting = phase
            }
        }
    }

    deinit {
        observer?.cancel()
    }
}
