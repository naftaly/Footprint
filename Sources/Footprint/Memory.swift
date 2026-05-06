///
///  Memory.swift
///  Footprint
///
///  Copyright (c) 2023 Alexander Cohen. All rights reserved.
///

import Foundation

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
public extension Footprint {
    /// Describes which kind of change occurred between two consecutive
    /// `Memory` snapshots. Delivered to observers in the `changesKey` userInfo
    /// of `memoryDidChangeNotification`.
    enum ChangeType: Comparable, Sendable {
        /// `memory.app.state` transitioned to a new bucket.
        case state
        /// `memory.app.pressure` transitioned to a new bucket.
        case pressure
        /// `memory.system.state` transitioned to a new bucket.
        case headroom
        /// `memory.app.used` or `memory.system.remaining` moved by ~1 MB+.
        case footprint
    }

    /// A structure that represents the different values required for easier memory
    /// handling throughout your apps lifetime.
    struct Memory: Sendable {
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

            /// Derive a `State` from a `used` value and its enclosing `limit`.
            /// Returns `.normal` when `limit <= 0`.
            public static func from(used: Int64, limit: Int64) -> State {
                let usedRatio = limit > 0 ? Double(used) / Double(limit) : 0
                return usedRatio < 0.25 ? .normal :
                    usedRatio < 0.50 ? .warning :
                    usedRatio < 0.75 ? .urgent :
                    usedRatio < 0.90 ? .critical : .terminal
            }
        }

        /// App-specific memory values bounded by the app's own memory limit.
        public struct App: Sendable {
            /// The amount of app used memory. Equivalent to `task_vm_info_data_t.phys_footprint`.
            public let used: Int64
            /// The amount of memory remaining to the app. Equivalent to `task_vm_info_data_t.limit_bytes_remaining`
            /// or `os_proc_available_memory`.
            public let remaining: Int64
            /// The high watermark of memory bytes your app can use before being terminated.
            public let limit: Int64
            /// Bytes of the app's footprint that the kernel currently has compressed.
            /// Equivalent to `task_vm_info_data_t.compressed`. Pages counted here are
            /// already included in `used`; this value is informational and useful for
            /// understanding how much of the footprint is sitting in the compressor.
            public let compressed: Int64
            /// The state describing where your app sits within the scope of its memory limit.
            public let state: State
            /// The state of memory pressure (aka. how close the app is to being Jetsamed/Jetisoned).
            public let pressure: State

            init(used: Int64, remaining: Int64, compressed: Int64, pressure: State) {
                self.used = used
                self.remaining = remaining
                self.compressed = compressed
                self.pressure = pressure
                limit = used + remaining
                state = State.from(used: used, limit: limit)
            }
        }

        /// System-wide memory values independent of the app's memory limit.
        public struct System: Sendable {
            /// Total physical memory on the device.
            public let limit: Int64
            /// Currently free physical memory on the device.
            public let remaining: Int64
            /// The state describing where the device sits within the scope of its
            /// physical memory limit.
            public let state: State

            init(limit: Int64, remaining: Int64) {
                self.limit = limit
                self.remaining = remaining
                state = State.from(used: max(limit - remaining, 0), limit: limit)
            }
        }

        /// App-specific memory information.
        public let app: App

        /// System-wide memory information.
        public let system: System

        /// The time at which this snapshot was taken in monotonic milliseconds of uptime.
        public let timestamp: UInt64

        init(app: App, system: System) {
            self.app = app
            self.system = system

            timestamp = {
                let timeInNanoseconds = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                return timeInNanoseconds / NSEC_PER_MSEC
            }()
        }
    }
}
