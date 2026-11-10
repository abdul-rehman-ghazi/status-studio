import Foundation

/// Renders one reel at a time (spec §5, FR-9). Main queue only.
final class ReelRenderer {
    struct Listener {
        let onProgress: (Double) -> Void
        let onDone: (String) -> Void
        let onError: (String) -> Void
    }

    private var current: RenderJob?

    var isBusy: Bool { current != nil }

    /// Busy until the render ends, fails or is cancelled. A spec that can't be rendered is
    /// reported through `listener.onError`, once the video has been opened.
    func start(_ spec: RenderSpec, listener: Listener) {
        let job = RenderJob(
            spec: spec,
            callbacks: RenderCallbacks(
                progress: { [weak self] fraction in
                    if self?.current != nil { listener.onProgress(fraction) }
                },
                finished: { [weak self] result in
                    self?.current = nil
                    switch result {
                    case .success: listener.onDone(spec.outputPath)
                    case .failure(let error): listener.onError(error.localizedDescription)
                    }
                }
            )
        )
        current = job
        job.start()
    }

    /// Stops the render and deletes the partial file (FR-9).
    func cancel() {
        current?.cancel()
        current = nil
    }
}
