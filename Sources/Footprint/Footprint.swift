///
///  Footprint.swift
///  Footprint
///
///  Copyright (c) 2023 Alexander Cohen. All rights reserved.
///

import Foundation
import os

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
    /// A structure that represents the different values required for easier memory
    /// handling throughout your apps lifetime.
    public struct Memory: Sendable {
        /// State describes how close to app termination your app is based on memory.
        public enum State: Int, Sendable, Comparable, CaseIterable {
            /// Everything is good, no need to worry.
            case normal

            /// You're still doing ok, but start reducing memory usage.
            case warning

            /// Reduce your memory footprint now.
            case urgent

            /// Time is of the essence, memory usage is very high, reduce your footprint.
            case critical

            /// Termination is imminent. If you make it here, you haven't changed your
            /// memory usage behavior.
            /// Please revisit memory best practices and profile your app.
            case terminal

            public static func < (lhs: Self, rhs: Self) -> Bool {
                lhs.rawValue < rhs.rawValue
            }

            /// Init from String value
            public init?(_ value: String) {
                for c in Self.allCases {
                    if value == "\(c)" {
                        self = c
                        return
                    }
                }
                return nil
            }
        }

        /// The amount of app used memory. Equivalent to `task_vm_info_data_t.phys_footprint`.
        public let used: Int64

        /// The amount of memory remaining to the app. Equivalent to `task_vm_info_data_t.limit_bytes_remaining`
        /// or `os_proc_available_memory`.
        public let remaining: Int64

        /// The high watermark of memory bytes your app can use before being terminated.
        public let limit: Int64

        /// The state describing where your app sits within the scope of its memory limit.
        public let state: State

        /// The state of memory pressure (aka. how close the app is to being Jetsamed/Jetisoned).
        public let pressure: State

        /// The time at which this snapshot was taken in monotonic milliseconds of uptime.
        public let timestamp: UInt64

        /// System-wide memory values independent of the app's memory limit.
        public struct System: Sendable {
            /// Total physical memory on the device.
            public let limit: Int64
            /// Currently free physical memory on the device.
            public let remaining: Int64
        }

        /// System-wide memory information.
        public let system: System

        /// Initialize for the `Memory` structure.
        init(
            used: Int64,
            remaining: Int64,
            compressed: Int64 = 0,
            pressure: State = .normal,
            system: System = System(limit: 0, remaining: 0)
        ) {
            self.used = used
            self.remaining = remaining
            limit = used + remaining
            self.compressed = compressed
            self.pressure = pressure
            self.system = system

            let usedRatio = limit > 0 ? Double(used) / Double(limit) : 0
            state = usedRatio < 0.25 ? .normal :
                usedRatio < 0.50 ? .warning :
                usedRatio < 0.75 ? .urgent :
                usedRatio < 0.90 ? .critical : .terminal

            timestamp = {
                let timeInNanoseconds = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                return timeInNanoseconds / NSEC_PER_MSEC
            }()
        }

        private let compressed: Int64
    }

    /// The footprint instance that is used throughout the lifetime of your app.
    ///
    /// Although the first call to this method can be made an any point,
    /// it is best to call this API as soon as possible at startup.
    public static let shared = Footprint()

    /// Notification name sent when the Footprint.Memory.state and/or
    /// Footprint.Memory.pressure changes.
    ///
    /// The notification userInfo dict will contain the `.oldMemoryKey`,
    /// `.newMemoryKey` and `.changesKey` keys.
    public static let memoryDidChangeNotification: NSNotification.Name = .init("FootprintMemoryDidChangeNotification")

    /// Key for the previous value of the memory state in the the
    /// `.stateDidChangeNotification` userInfo object.
    /// Value type is `Footprint.Memory`.
    public static let oldMemoryKey: String = "oldMemory"

    /// Key for the new value of the memory state in the the `.stateDidChangeNotification`
    /// userInfo object. Value type is `Footprint.Memory`.
    public static let newMemoryKey: String = "newMemory"

    /// Key for the changes of the memory in the the `.stateDidChangeNotification`
    /// userInfo object. Value type is `Set<ChangeType>`
    public static let changesKey: String = "changes"

    /// Types of changes possible
    public enum ChangeType: Comparable, Sendable {
        case state
        case pressure
        case footprint
    }

    /// Returns a copy of the current memory structure.
    public var memory: Memory {
        _memoryLock.withLock { _memory }
    }

    /// Returns an AsyncStream that pushes a _Memory_ as it changes.
    public var memoryStream: AsyncStream<Memory> {
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
    public func canAllocate(bytes: UInt64) -> Bool {
        bytes < provideMemory().remaining
    }

    /// The currently tracked memory state.
    public var state: Memory.State {
        _memoryLock.withLock { _memory.state }
    }

    /// The currently tracked memory pressure.
    public var pressure: Memory.State {
        _memoryLock.withLock { _memory.pressure }
    }

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
        _timerSource.suspend()
        _timerSource.cancel()

        _memoryPressureSource.suspend()
        _memoryPressureSource.cancel()

        _observerNotificationSource.suspend()
        _observerNotificationSource.cancel()

        _memoryLock.withLock {
            _memoryStreamContinuations.values.forEach { $0.finish() }
            _memoryStreamContinuations.removeAll()
        }
    }

    private func heartbeat() {
        let memory = provideMemory()
        coalesce(with: memory)
        #if targetEnvironment(simulator)
            // In the simulator there are no memory terminations,
            // so we fake one.
            if memory.state == .terminal {
                // Anything in this env var will enable this
                if ProcessInfo.processInfo.environment["SIM_FOOTPRINT_OOM_TERM_ENABLED"] != nil {
                    print("Footprint: exiting due to the memory limit")
                    kill(getpid(), SIGKILL)
                    _exit(EXIT_FAILURE)
                }
            }
        #endif
    }

    private func provideMemory() -> Memory {
        _provider.provide(currentPressureFromSource())
    }

    private func currentPressureFromSource() -> Memory.State {
        if _memoryPressureSource.data.contains(.critical) {
            return .critical
        } else if _memoryPressureSource.data.contains(.warning) {
            return .warning
        }
        return .normal
    }

    public func observe(_ action: @escaping @Sendable (Memory) -> Void) {
        let mem = _memoryLock.withLock {
            _observers.append(action)
            return _memory
        }
        _queue.async {
            action(mem)
        }
    }

    private func coalesce(with memory: Memory) {
        // If nothing changed, then there's nothing to add
        guard _memoryLock.withLock({
            let hasChanges = (_memory.state != memory.state ||
                _memory.pressure != memory.pressure ||
                abs(_memory.used - memory.used) > 1_000_000 ||
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

    private func sendObservers() {
        // Compare last notified state with current state to calculate aggregate changes
        _memoryLock.lock()
        let oldMemory = _lastNotifiedMemory
        let newMemory = _memory

        // Calculate what changed since last notification
        var changeSet: Set<ChangeType> = []
        if oldMemory.state != newMemory.state {
            changeSet.insert(.state)
            changeSet.insert(.footprint)
        }
        if oldMemory.pressure != newMemory.pressure {
            changeSet.insert(.pressure)
            changeSet.insert(.footprint)
        }
        // memory used changes only on ~1MB intervals
        if abs(oldMemory.used - newMemory.used) > 1_000_000 {
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

        // Send all observers outside of the lock on the main queue.
        // main queue is important since most of us will want to
        // make changes that might touch the UI.
        if changeSet.contains(.pressure) || changeSet.contains(.state) {
            // Create isolated copies for the main actor closure
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

        // Send footprint observers
        if changeSet.contains(.footprint) {
            observers.forEach { $0(newMemory) }
            continuations.forEach { $0.yield(newMemory) }
        }
    }

    private let _queue = DispatchQueue(label: "com.bedroomcode.footprint.heartbeat.queue", qos: .utility, target: DispatchQueue.global(qos: .utility))
    private let _timerSource: DispatchSourceTimer
    private let _heartbeatInterval = 500 // milliseconds
    private let _provider: MemoryProvider
    private let _memoryPressureSource: DispatchSourceMemoryPressure
    private let _observerNotificationSource: DispatchSourceUserDataAdd

    private var _observers: [@Sendable (Memory) -> Void] = []
    private let _memoryLock: NSLock = .init()
    private var _memory: Memory
    private var _lastNotifiedMemory: Memory
    private var _memoryStreamContinuations: [UUID: AsyncStream<Memory>.Continuation] = [:]
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
public protocol MemoryProvider {
    func provide(_ pressure: Footprint.Memory.State) -> Footprint.Memory
}

#if canImport(SwiftUI)
    import SwiftUI

    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
    public extension View {
        /// A SwiftUI extension providing a convenient way to observe changes in the memory
        /// state of the app through the `onFootprintMemoryDidChange` modifier.
        ///
        /// ## Overview
        ///
        /// The `onFootprintMemoryDidChange` extension allows you to respond
        /// to changes in the app's memory state and pressure by providing a closure that is executed
        /// whenever the memory state transitions. You can also use specific modifiers for
        /// state (`onFootprintMemoryStateDidChange`) or
        /// pressure (`onFootprintMemoryPressureDidChange`).
        ///
        /// ### Example Usage
        ///
        /// ```swift
        /// Text("Hello, World!")
        ///     .onFootprintMemoryDidChange { newMemory, oldMemory, changeSet in
        ///         print("Memory state changed from \(oldState) to \(newState)")
        ///         // Perform actions based on the memory change
        ///     }
        @inlinable func onFootprintMemoryDidChange(perform action: @escaping (_ state: Footprint.Memory, _ previousState: Footprint.Memory, _ changes: Set<Footprint.ChangeType>) -> Void) -> some View {
            _ = Footprint.shared // make sure it's running
            return onReceive(NotificationCenter.default.publisher(for: Footprint.memoryDidChangeNotification)) { note in
                if let changes = note.userInfo?[Footprint.changesKey] as? Set<Footprint.ChangeType>,
                   let memory = note.userInfo?[Footprint.newMemoryKey] as? Footprint.Memory,
                   let prevMemory = note.userInfo?[Footprint.oldMemoryKey] as? Footprint.Memory
                {
                    action(memory, prevMemory, changes)
                }
            }
        }

        @inlinable func onFootprintMemoryStateDidChange(perform action: @escaping (_ state: Footprint.Memory.State, _ previousState: Footprint.Memory.State) -> Void) -> some View {
            _ = Footprint.shared // make sure it's running
            return onReceive(NotificationCenter.default.publisher(for: Footprint.memoryDidChangeNotification)) { note in
                if let changes = note.userInfo?[Footprint.changesKey] as? Set<Footprint.ChangeType>,
                   changes.contains(.state),
                   let memory = note.userInfo?[Footprint.newMemoryKey] as? Footprint.Memory,
                   let prevMemory = note.userInfo?[Footprint.oldMemoryKey] as? Footprint.Memory
                {
                    action(memory.state, prevMemory.state)
                }
            }
        }

        @inlinable func onFootprintMemoryPressureDidChange(perform action: @escaping (_ pressure: Footprint.Memory.State, _ previousPressure: Footprint.Memory.State) -> Void) -> some View {
            _ = Footprint.shared // make sure it's running
            return onReceive(NotificationCenter.default.publisher(for: Footprint.memoryDidChangeNotification)) { note in
                if let changes = note.userInfo?[Footprint.changesKey] as? Set<Footprint.ChangeType>,
                   changes.contains(.pressure),
                   let memory = note.userInfo?[Footprint.newMemoryKey] as? Footprint.Memory,
                   let prevMemory = note.userInfo?[Footprint.oldMemoryKey] as? Footprint.Memory
                {
                    action(memory.pressure, prevMemory.pressure)
                }
            }
        }
    }

#endif
