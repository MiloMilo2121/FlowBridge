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

/// Returns a fallback at a hard deadline even when the work ignores
/// cancellation. Structured task groups wait for every child before leaving
/// scope, so they cannot protect a user-facing delivery path from a stuck
/// framework call; this deliberately races unstructured producers instead.
public enum TaskDeadline {
    public struct Outcome<Value: Sendable>: Sendable {
        public let value: Value
        public let timedOut: Bool

        public init(value: Value, timedOut: Bool) {
            self.value = value
            self.timedOut = timedOut
        }
    }

    public static func value<Value: Sendable>(
        from work: Task<Value, Never>,
        fallback: Value,
        after budget: Duration
    ) async -> Outcome<Value> {
        let stream = AsyncStream<Outcome<Value>> { continuation in
            Task {
                continuation.yield(Outcome(value: await work.value, timedOut: false))
                continuation.finish()
            }
            Task {
                do {
                    try await Task.sleep(for: budget)
                } catch {
                    return
                }
                continuation.yield(Outcome(value: fallback, timedOut: true))
                continuation.finish()
            }
        }

        var iterator = stream.makeAsyncIterator()
        let outcome = await iterator.next() ?? Outcome(value: fallback, timedOut: true)
        if outcome.timedOut {
            work.cancel()
        }
        return outcome
    }
}
