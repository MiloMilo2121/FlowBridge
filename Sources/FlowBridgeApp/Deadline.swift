import Foundation

/// Races `operation` against a hard deadline and never waits for an
/// operation that ignores cancellation.
///
/// A `TaskGroup` awaits *every* child before its body returns, so a single
/// child that ignores cancellation (a model load blocked in a system
/// framework, a decode that won't unwind) silently voids the very deadline
/// the group was supposed to enforce. Here the operation runs in a detached
/// task that publishes its outcome through a one-shot hand-off, and the timer
/// publishes a timeout into the same hand-off. Whichever arrives first
/// resumes the caller; nothing is awaited twice and nothing is left
/// suspended.
///
/// The abandoned operation therefore still owns whatever it allocated (a
/// half-started audio session, a loaded model) and is *not* cancelled —
/// that is the point. `onAbandon` is how it releases that: it runs after
/// the operation finally unwinds, never before.
///
/// - Parameters:
///   - timeout: how long the caller is willing to wait.
///   - onTimeout: the value (or error) to produce when the deadline wins.
///   - operation: the work to race. Not a child of the caller's task.
///   - onAbandon: cleanup for work that is still in flight at the deadline.
func withDeadline<T: Sendable>(
    _ timeout: Duration,
    onTimeout: @escaping @Sendable () throws -> T,
    operation: @escaping @Sendable () async throws -> T,
    onAbandon: (@Sendable () async -> Void)? = nil
) async throws -> T {
    let handoff = ResultHandoff<T>()

    let work = Task {
        do {
            let value = try await operation()
            // Lost the race: nobody will ever read this value, and this task
            // is the only place that can release what the operation owns.
            if !handoff.resolve(.success(value)) {
                await onAbandon?()
            }
        } catch {
            if !handoff.resolve(.failure(error)) {
                await onAbandon?()
            }
        }
    }

    // The deadline produces its outcome through `onTimeout`, so a caller
    // can pick either a fallback value or a domain error (`warmupTimedOut`).
    let timer = Task {
        try? await Task.sleep(for: timeout)
        // Cancelled means the race is already decided: don't run a
        // fallback (or build a domain error) nobody will read.
        guard !Task.isCancelled else { return }
        do {
            handoff.resolve(.success(try onTimeout()))
        } catch {
            handoff.resolve(.failure(error))
        }
    }

    // Cancellation of the caller is honoured too, and needs no cooperation
    // from `operation`: it only stops us waiting.
    let result = await withTaskCancellationHandler {
        await handoff.wait()
    } onCancel: {
        handoff.resolve(.failure(CancellationError()))
    }

    timer.cancel()
    return try result.get()
}

/// One-shot hand-off: the first of {operation result, timeout, caller
/// cancellation} wins, and the loser learns it lost by getting `false` from
/// `resolve` instead of a delivered value.
private final class ResultHandoff<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?
    private var continuation: CheckedContinuation<Result<T, Error>, Never>?

    /// Resolves a waiter if there still is one. False means the value was
    /// dropped because someone else already won.
    @discardableResult
    func resolve(_ newResult: Result<T, Error>) -> Bool {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return false
        }
        result = newResult
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: newResult)
        return true
    }

    func wait() async -> Result<T, Error> {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }
}
