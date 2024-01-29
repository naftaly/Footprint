MIT License

Copyright (c) 2024 Alexander Cohen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

import Foundation
import UIKit

/// The footprint manages snapshots of app memory limits and state,
/// and notifies your app when these change.
///
/// For the longest time, Apple platform engineers have been taught to be careful with memory,
/// and if there is an issue, a notification will tell you when to drop objects and you should be ok.
/// This works well for smaller apps, but as soon as your app grows you start finding that these
/// notifications come too late and with too many restrictions.

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

/// A simple use example is with caches. You could change the maximum cost
/// of said cache based on the `.State`. Say, `.normal` has a 100% multiplier,
///`.warning` is 80%, `.critical` is 50%  and so on. This leads to your
/// caches being purged based on the users behavior and the memory footprint
/// used by your app has a much lower upper bound and much smaller drops.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public class Footprint {
    
    /// A structure that represents the different values required for easier memory hamlding throughout your apps lifetime.
    public struct Memory {
        
        /// State describes how close to app termination your app is based on memory.
        public enum State: Int {
            /// Everything is good, no need to worry.
            case normal
            
            /// You're still doing ok, but start reducing memory usage.
            case warning
            
            /// Time is of the essence, memory usage is very high, reduce your footprint.
            case critical
            
            /// Termination is imminent. If you make it here, you haven't changed your memory usage behavior.
            /// Please revisit memory best practices and profile your app.
            case terminal
        }
        
        /// The amount of app used memory. Equivalent to `task_vm_info_data_t.phys_footprint`.
        public let used: Int
        
        /// The amount of memory remaining to the app. Equivalent to `task_vm_info_data_t.limit_bytes_remaining`
        /// or `os_proc_available_memory`.
        public let remaining: Int
        
        /// The high watermark of memory bytes your app can use before being terminated.
        public let limit: Int
        
        /// The state describing where your app sits within the scope of its memory limit.
        public let state: State
        
        init() {
            var info = task_vm_info_data_t()
            var infoCount = TASK_VM_INFO_COUNT
            
            let kerr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, thread_flavor_t(TASK_VM_INFO), $0, &infoCount)
                }
            }
            used = kerr == KERN_SUCCESS ? Int(info.phys_footprint) : 0
            compressed = kerr == KERN_SUCCESS ? Int(info.compressed) : 0
#if targetEnvironment(simulator)
            // In the simulator `limit_bytes_remaining` returns -1
            // which means we can't calculate limits.
            // Due to this, we just set it to 4GB.
            limit = Int(4e+9)
            remaining = max(limit - used, 0)
#else
            remaining = kerr == KERN_SUCCESS ? Int(info.limit_bytes_remaining) : 0
            limit = used + remaining
#endif
            
            usedRatio = Double(used)/Double(limit)
            state = usedRatio < 0.30 ? .normal : usedRatio < 0.50 ? .warning : usedRatio < 0.85 ? .critical : .terminal
        }
        
        private let compressed: Int
        private let usedRatio: Double
        private let TASK_BASIC_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_basic_info_data_t>.size /  MemoryLayout<UInt32>.size)
        private let TASK_VM_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<UInt32>.size)
    }
    
    /// The footprint instance that is used throughout the lifetime of your app.
    ///
    /// Although the first call to this method can be made an any point, it is best to call this API as soon as possible at startup.
    public static let shared = Footprint()
    
    
    /// Notification name sent when the Footprint.Memory.state changes.
    ///
    /// The notification userInfo dict will contain they `.oldMemoryStateKey` and `.newMemoryStateKey` keys.
    public static let stateDidChangeNotification: NSNotification.Name = NSNotification.Name("FootprintMemoryStateDidChangeNotification")
    
    /// Key for the previous value of the memory state in the the `.stateDidChangeNotification` userInfo object.
    public static let oldMemoryStateKey: String = "oldMemoryState"
    
    /// Key for the new value of the memory statein the the `.stateDidChangeNotification` userInfo object.
    public static let newMemoryStateKey: String = "newMemoryState"
    
    /// Returns the current memory structure.
    public var memory: Memory {
        return Memory()
    }
    
    /// Based on the current memory footprint, tells you if you should be able to allocate a certain amount of memory.
    ///
    /// - Parameter bytes: The number of bytes you are interested in allocating.
    ///
    /// - returns: A `Bool` indicating if allocating `bytes` will likely work.
    public func canAllocate(bytes: UInt) -> Bool {
        return bytes < Memory().remaining
    }
    
    /// The currently tracked memory state.
    public var state: Memory.State {
        get {
            _stateLock.lock()
            defer { _stateLock.unlock() }
            return _state
        }
    }
    
    
    private init() {
        _state = Memory().state
        
        let timerSource = DispatchSource.makeTimerSource(queue: _queue)
        timerSource.schedule(deadline: .now(), repeating: .milliseconds(500), leeway: .milliseconds(500))
        timerSource.setEventHandler { [weak self] in
            self?.heartbeat()
        }
        timerSource.activate()
        _timerSource = timerSource
    }
    
    deinit {
        _timerSource?.suspend()
        _timerSource?.cancel()
        _timerSource = nil
    }
    
    private func heartbeat() {
        let memory = memory
        sendObservers(for: memory.state)
#if targetEnvironment(simulator)
        // In the simulator there are no memory terminations,
        // so we fake one.
        if memory.state == .terminal {
            print("Footprint: exiting due to the memory limit")
            _exit(EXIT_FAILURE)
        }
#endif
    }
    
    private func sendObservers(for state: Memory.State) {
        _stateLock.lock()
        defer { _stateLock.unlock() }
        
        let oldState = _state
        _state = state
        
        // send all observers outside of the lock on the main queue.
        // main queue is important since most of us will want to
        // make changes that might touch the UI.
        if oldState != state {
            print("Footprint.state \(state)")
            DispatchQueue.main.sync {
                NotificationCenter.default.post(name: Footprint.stateDidChangeNotification, object: nil, userInfo: [
                    Footprint.newMemoryStateKey: state,
                    Footprint.oldMemoryStateKey: oldState
                ])
            }
        }
        
    }
    
    private let _queue = DispatchQueue(label: "com.bedroomcode.footprint.heartbeat.queue", qos: .utility, target: DispatchQueue.global(qos: .utility))
    private var _timerSource: DispatchSourceTimer? = nil
    
    private var _stateLock: NSLock = NSLock()
    private var _state: Memory.State
}

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension View {
    
    /// A SwiftUI extension providing a convenient way to observe changes in the memory state of the app through the `onFootprintMemoryStateDidChange` modifier.
    ///
    /// ## Overview
    ///
    /// The `onFootprintMemoryStateDidChange` extension allows you to respond to changes in the app's memory state by providing a closure that is executed whenever the memory state transitions.
    ///
    /// ### Example Usage
    ///
    /// ```swift
    /// Text("Hello, World!")
    ///     .onFootprintMemoryStateDidChange { newState, oldState in
    ///         print("Memory state changed from \(oldState) to \(newState)")
    ///         // Perform actions based on the memory state change
    ///     }
    @inlinable public func onFootprintMemoryStateDidChange(perform action: @escaping (_ state: Footprint.Memory.State, _ previousState: Footprint.Memory.State) -> Void) -> some View {
        return onReceive(NotificationCenter.default.publisher(for: Footprint.stateDidChangeNotification)) { note in
            if let state = note.userInfo?[Footprint.newMemoryStateKey] as? Footprint.Memory.State,
               let prevState = note.userInfo?[Footprint.oldMemoryStateKey] as? Footprint.Memory.State {
                action(state, prevState)
            }
        }
    }
    
}

#endif
