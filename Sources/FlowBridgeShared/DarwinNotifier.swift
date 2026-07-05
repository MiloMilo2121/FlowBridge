import Foundation

#if canImport(Darwin)
import CoreFoundation
#endif

/// Cross-process wakeups between the main app and its extensions.
///
/// Darwin notifications carry no payload; they only signal "something
/// changed". The payload always lives in the App Group (see
/// `LiveTranscriptStore`), so a missed notification degrades to a slightly
/// staler read, never to data loss. On non-Darwin platforms (the Linux
/// `FlowBridgeSharedCheck` build) posting is a no-op and observers never
/// fire; callers keep a low-frequency timer as the fallback path.
public enum DarwinNotifier {
    public static func post(_ name: String) {
        #if canImport(Darwin)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
        #endif
    }
}

/// Observes one Darwin notification name for the lifetime of the instance.
/// Deallocate (or hold `nil`) to stop observing.
///
/// Delivery goes through a lock-protected static registry keyed by the
/// observer pointer: the C callback never dereferences the instance, so a
/// notification racing with deallocation on another thread can at worst hit
/// a missing registry entry — never freed memory.
public final class DarwinNotificationObserver: @unchecked Sendable {
    private struct Entry {
        let queue: DispatchQueue
        let handler: @Sendable () -> Void
    }

    private static let registryLock = NSLock()
    private nonisolated(unsafe) static var registry: [UnsafeRawPointer: Entry] = [:]

    private let name: String

    public init(name: String, queue: DispatchQueue = .main, handler: @escaping @Sendable () -> Void) {
        self.name = name

        let key = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        Self.registryLock.lock()
        Self.registry[key] = Entry(queue: queue, handler: handler)
        Self.registryLock.unlock()

        #if canImport(Darwin)
        let callback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer else { return }
            let key = UnsafeRawPointer(observer)
            DarwinNotificationObserver.registryLock.lock()
            let entry = DarwinNotificationObserver.registry[key]
            DarwinNotificationObserver.registryLock.unlock()
            guard let entry else { return }
            entry.queue.async(execute: entry.handler)
        }

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            callback,
            name as CFString,
            nil,
            .deliverImmediately
        )
        #endif
    }

    deinit {
        #if canImport(Darwin)
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name as CFString),
            nil
        )
        #endif

        let key = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        Self.registryLock.lock()
        Self.registry.removeValue(forKey: key)
        Self.registryLock.unlock()
    }
}
