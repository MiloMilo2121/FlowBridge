import Foundation

/// A tiny re-entrancy gate for actor- or main-actor-isolated async operations.
///
/// Async functions can be re-entered whenever they `await`. Callers keep this
/// value on their isolated owner, enter before the first suspension point, and
/// leave in a `defer` block.
public struct AsyncOperationGate: Sendable {
    public private(set) var isEntered = false

    public init() {}

    public mutating func enterIfAvailable() -> Bool {
        guard !isEntered else { return false }
        isEntered = true
        return true
    }

    public mutating func leave() {
        isEntered = false
    }
}

/// Cancels a child task and waits until its cleanup has actually completed.
/// Cancellation alone is only a request; releasing hardware before the task
/// has observed it can let late work recreate resources after teardown.
public enum TaskQuiescer {
    public static func cancelAndWait(_ task: Task<Void, Never>?) async {
        guard let task else { return }
        task.cancel()
        await task.value
    }
}
