import Foundation
import UIKit

/// Whether the app may still use the GPU. iOS refuses GPU work from the background, and Core
/// Image would then draw nothing without saying so, so the frame loop waits here while the app
/// is not in front, even when a background task keeps the process running (spec FR-16).
final class ForegroundGate {
    private static let recheckSeconds = 0.25

    private let condition = NSCondition()
    private var isActive = true

    /// Created on the main queue, where the app's state may be read.
    init() {
        isActive = UIApplication.shared.applicationState == .active
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.set(inFront: false)
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.set(inFront: true)
        }
    }

    var isInFront: Bool {
        condition.lock()
        defer { condition.unlock() }
        return isActive
    }

    /// Blocks the calling queue until the app is in front again, or `isStopped` says the render
    /// ended meanwhile.
    func waitUntilInFront(unlessStopped isStopped: () -> Bool) {
        condition.lock()
        defer { condition.unlock() }
        while !isActive, !isStopped() {
            _ = condition.wait(until: Date(timeIntervalSinceNow: ForegroundGate.recheckSeconds))
        }
    }

    private func set(inFront: Bool) {
        condition.lock()
        isActive = inFront
        condition.broadcast()
        condition.unlock()
    }
}
