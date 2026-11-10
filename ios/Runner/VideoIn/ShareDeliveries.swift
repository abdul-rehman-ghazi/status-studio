import Foundation

/// Hands each finished share to Dart: pushed at once while Dart listens, kept otherwise. Dart
/// collects what was kept when it starts listening again. Main thread only.
final class ShareDeliveries {
    private let push: (_ method: String, _ arguments: [String: Any]) -> Void
    private var waiting: [[String: Any]] = []
    private var dartIsListening = false

    init(push: @escaping (_ method: String, _ arguments: [String: Any]) -> Void) {
        self.push = push
    }

    func deliver(method: String, arguments: [String: Any]) {
        guard dartIsListening else {
            waiting.append(["method": method, "arguments": arguments])
            return
        }
        push(method, arguments)
    }

    func startListening() -> [[String: Any]] {
        dartIsListening = true
        let kept = waiting
        waiting = []
        return kept
    }

    func stopListening() {
        dartIsListening = false
    }
}
