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
public final class DarwinNotificationObserver: @unchecked Sendable {
    private let name: String
    private let queue: DispatchQueue
    private let handler: @Sendable () -> Void

    public init(name: String, queue: DispatchQueue = .main, handler: @escaping @Sendable () -> Void) {
        self.name = name
        self.queue = queue
        self.handler = handler

        #if canImport(Darwin)
        let callback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer else { return }
            let instance = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
            instance.queue.async {
                instance.handler()
            }
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
    }
}
