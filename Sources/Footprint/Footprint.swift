///
///  Footprint.swift
///  Footprint
///
///  Copyright (c) 2023 Alexander Cohen. All rights reserved.
///

import Foundation

/// The footprint manages snapshots of app memory limits and state,
/// and notifies your app when these change.
///
/// For the longest time, Apple platform engineers have been taught to be careful with memory,
/// and if there is an issue, a notification will tell you when to drop objects and you should be ok.
/// This works well for smaller apps, but as soon as your app grows you start finding that these
/// notifications come too late and with too many restrictions.
///
/// Later came `os_proc_available_memory` which gives us the amount of memory left
/// to our apps before they are terminated. Now we're getting somewhere, we can finally tell if
/// memory was the actual reason for being terminated. But again, we're still missing the upper
/// bound. Say we have 1GB of memory remaining, wouldn't it be useful to know how much
/// we've actually used, wouldn't it be useful to be able to **change the apps behavior based on
/// where our app stands within the bounds of the memory limit**?
///
/// This is where `Footprint` comes in. It gives you the opportunity to handle memory in
/// levels (Footprint.Memory.State) instead of all at once at the end. It expects you to change
/// your apps behavior as your users explore.
///
/// A simple use example is with caches. You could change the maximum cost
/// of said cache based on the `.State`. Say, `.normal` has a 100% multiplier,
/// `.warning` is 80%, `.critical` is 50%  and so on. This leads to your
/// caches being purged based on the users behavior and the memory footprint
/// used by your app has a much lower upper bound and much smaller drops.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
public final class Footprint: @unchecked Sendable {
    init(_ provider: MemoryProvider = DefaultMemoryProvider()) {
        _provider = provider
        _memory = _provider.provide(.normal)
        _lastNotifiedMemory = _memory

        _timerSource = DispatchSource.makeTimerSource(queue: _queue)
        _memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.all], queue: _queue)
        _observerNotificationSource = DispatchSource.makeUserDataAddSource(queue: _queue)

        _timerSource.schedule(deadline: .now(), repeating: .milliseconds(500), leeway: .milliseconds(500))
        _timerSource.setEventHandler { [weak self] in
            self?.heartbeat()
        }
        _memoryPressureSource.setEventHandler { [weak self] in
            self?.heartbeat()
        }
        _observerNotificationSource.setEventHandler { [weak self] in
            self?.sendObservers()
        }

        _timerSource.activate()
        _memoryPressureSource.activate()
        _observerNotificationSource.activate()
    }

    deinit {
        // Cancel without suspending - suspending an active source and then
        // releasing it without resuming traps in libdispatch. Cancellation
        // alone is sufficient to stop further event delivery.
        _timerSource.cancel()
        _memoryPressureSource.cancel()
        _observerNotificationSource.cancel()

        _memoryLock.withLock {
            _memoryStreamContinuations.values.forEach { $0.finish() }
            _memoryStreamContinuations.removeAll()
        }
    }

    fileprivate let _queue = DispatchQueue(label: "com.bedroomcode.footprint.heartbeat.queue", qos: .utility, target: DispatchQueue.global(qos: .utility))
    fileprivate let _timerSource: DispatchSourceTimer
    fileprivate let _heartbeatInterval = 500 // milliseconds
    fileprivate let _provider: MemoryProvider
    fileprivate let _memoryPressureSource: DispatchSourceMemoryPressure
    fileprivate let _observerNotificationSource: DispatchSourceUserDataAdd

    fileprivate var _observers: [@Sendable (Memory) -> Void] = []
    fileprivate let _memoryLock: NSLock = .init()
    fileprivate var _memory: Memory
    fileprivate var _lastNotifiedMemory: Memory
    fileprivate var _memoryStreamContinuations: [UUID: AsyncStream<Memory>.Continuation] = [:]
}

// MARK: - Public API constants

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
public extension Footprint {
    /// The footprint instance that is used throughout the lifetime of your app.
    ///
    /// Although the first call to this method can be made an any point,
    /// it is best to call this API as soon as possible at startup.
    static let shared = Footprint()

    /// Notification name sent when `memory.app.state`, `memory.app.pressure`,
    /// or `memory.system.state` transitions to a new bucket.
    ///
    /// The notification userInfo dict will contain the `oldMemoryKey`,
    /// `newMemoryKey`, and `changesKey` entries.
    static let memoryDidChangeNotification: NSNotification.Name = .init("FootprintMemoryDidChangeNotification")

    /// Key for the previous `Footprint.Memory` snapshot in the
    /// `memoryDidChangeNotification` userInfo dict.
    static let oldMemoryKey: String = "oldMemory"

    /// Key for the new `Footprint.Memory` snapshot in the
    /// `memoryDidChangeNotification` userInfo dict.
    static let newMemoryKey: String = "newMemory"

    /// Key for the `Set<ChangeType>` describing what transitioned, in the
    /// `memoryDidChangeNotification` userInfo dict.
    static let changesKey: String = "changes"
}

// MARK: - State accessors

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
public extension Footprint {
    /// The currently tracked memory state.
    var state: Memory.State {
        _memoryLock.withLock { _memory.app.state }
    }

    /// The currently tracked memory pressure.
    var pressure: Memory.State {
        _memoryLock.withLock { _memory.app.pressure }
    }

    /// The currently tracked system memory headroom (the state of device-wide
    /// physical memory, equivalent to `memory.system.state`).
    var headroom: Memory.State {
        _memoryLock.withLock { _memory.system.state }
    }
}

// MARK: - Observation

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
public extension Footprint {
    /// Returns a copy of the current memory structure.
    var memory: Memory {
        _memoryLock.withLock { _memory }
    }

    /// Returns an AsyncStream that pushes a _Memory_ as it changes.
    var memoryStream: AsyncStream<Memory> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self._memoryLock.withLock {
                    _ = self._memoryStreamContinuations.removeValue(forKey: id)
                }
            }
            _memoryLock.withLock {
                _memoryStreamContinuations[id] = continuation
            }
        }
    }

    /// Based on the current memory footprint, tells you if you should be able to allocate
    /// a certain amount of memory.
    ///
    /// - Parameter bytes: The number of bytes you are interested in allocating.
    ///
    /// - returns: A `Bool` indicating if allocating `bytes` will likely work.
    func canAllocate(bytes: UInt64) -> Bool {
        bytes < provideMemory().app.remaining
    }

    func observe(_ action: @escaping @Sendable (Memory) -> Void) {
        let mem = _memoryLock.withLock {
            _observers.append(action)
            return _memory
        }
        _queue.async {
            action(mem)
        }
    }
}

// MARK: - Internal coordination

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
fileprivate extension Footprint {
    func heartbeat() {
        let memory = provideMemory()
        coalesce(with: memory)
        #if targetEnvironment(simulator)
            // In the simulator there are no memory terminations,
            // so we fake one.
            if memory.app.state == .terminal {
                // Anything in this env var will enable this
                if ProcessInfo.processInfo.environment["SIM_FOOTPRINT_OOM_TERM_ENABLED"] != nil {
                    print("Footprint: exiting due to the memory limit")
                    kill(getpid(), SIGKILL)
                    _exit(EXIT_FAILURE)
                }
            }
        #endif
    }

    func provideMemory() -> Memory {
        _provider.provide(currentPressureFromSource())
    }

    func currentPressureFromSource() -> Memory.State {
        if _memoryPressureSource.data.contains(.critical) {
            return .critical
        } else if _memoryPressureSource.data.contains(.warning) {
            return .warning
        }
        return .normal
    }

    func coalesce(with memory: Memory) {
        // If nothing changed, then there's nothing to add
        guard _memoryLock.withLock({
            let hasChanges = (_memory.app.state != memory.app.state ||
                _memory.app.pressure != memory.app.pressure ||
                _memory.system.state != memory.system.state ||
                abs(_memory.app.used - memory.app.used) > 1_000_000 ||
                abs(_memory.system.remaining - memory.system.remaining) > 1_000_000) &&
                memory.timestamp - _memory.timestamp >= _heartbeatInterval
            if hasChanges {
                _memory = memory
            }
            return hasChanges
        }) else {
            return
        }

        // Changes detected, trigger coalesced notification
        _observerNotificationSource.add(data: 1)
    }

    func sendObservers() {
        // Compare last notified state with current state to calculate aggregate changes
        _memoryLock.lock()
        let oldMemory = _lastNotifiedMemory
        let newMemory = _memory

        // Calculate what changed since last notification
        var changeSet: Set<ChangeType> = []
        if oldMemory.app.state != newMemory.app.state {
            changeSet.insert(.state)
            changeSet.insert(.footprint)
        }
        if oldMemory.app.pressure != newMemory.app.pressure {
            changeSet.insert(.pressure)
            changeSet.insert(.footprint)
        }
        if oldMemory.system.state != newMemory.system.state {
            changeSet.insert(.headroom)
            changeSet.insert(.footprint)
        }
        // memory used changes only on ~1MB intervals
        if abs(oldMemory.app.used - newMemory.app.used) > 1_000_000 {
            changeSet.insert(.footprint)
        }
        if abs(oldMemory.system.remaining - newMemory.system.remaining) > 1_000_000 {
            changeSet.insert(.footprint)
        }

        guard !changeSet.isEmpty else {
            _memoryLock.unlock()
            return
        }

        // Update last notified memory
        _lastNotifiedMemory = newMemory

        // Copy observers/continuations behind the lock
        let observers = _observers
        let continuations = Array(_memoryStreamContinuations.values)
        _memoryLock.unlock()

        // NotificationCenter delivery is hopped to the main queue since most
        // observers will want to update UI in response. Closure observers
        // and AsyncStream continuations stay on `_queue` — callers that need
        // to touch the main thread should hop themselves.
        if changeSet.contains(.pressure) || changeSet.contains(.state) || changeSet.contains(.headroom) {
            let notificationNewMemory = newMemory
            let notificationOldMemory = oldMemory
            let notificationChangeSet = changeSet
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Footprint.memoryDidChangeNotification, object: nil, userInfo: [
                    Footprint.newMemoryKey: notificationNewMemory,
                    Footprint.oldMemoryKey: notificationOldMemory,
                    Footprint.changesKey: notificationChangeSet,
                ])
            }
        }

        if changeSet.contains(.footprint) {
            observers.forEach { $0(newMemory) }
            continuations.forEach { $0.yield(newMemory) }
        }
    }
}
