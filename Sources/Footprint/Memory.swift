//
//  Memory.swift
//  Footprint
//
//  Copyright (c) 2023 Alexander Cohen. All rights reserved.
//

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
        /// Footprint values changed in a way callers may want to react to.
        /// Always emitted alongside `.state`, `.pressure`, or `.headroom`,
        /// and additionally on its own when `memory.app.used` or
        /// `memory.system.remaining` move by ~1 MB+.
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
            ///
            /// `baseline` shifts the 25/50/75/90 ladder up the range, treating
            /// `[0, baseline]` as a "logical zero" that always reports `.normal`.
            /// The four danger thresholds then land at `baseline + 0.25 × (1 - baseline)`,
            /// `+ 0.50`, `+ 0.75`, `+ 0.90`. With the default `baseline = 0` the
            /// thresholds are the original 25/50/75/90.
            ///
            /// `System` passes `baseline = 0.80` because a ratio against
            /// `physicalMemory` is dominated by wired kernel pages and
            /// always-on system overhead; only the top ~20% of the range is
            /// meaningful headroom worth bucketing.
            ///
            /// `baseline` is clamped to `[0, 1]`; out-of-range values would
            /// otherwise collapse or invert the ladder.
            ///
            /// Returns `.normal` when `limit <= 0`.
            public static func from(used: Int64, limit: Int64, baseline: Double = 0) -> State {
                guard limit > 0 else { return .normal }
                let baseline = min(max(baseline, 0.0), 1.0)
                let usedRatio = Double(used) / Double(limit)
                let scale = 1.0 - baseline
                if usedRatio < baseline + 0.25 * scale { return .normal }
                if usedRatio < baseline + 0.50 * scale { return .warning }
                if usedRatio < baseline + 0.75 * scale { return .urgent }
                if usedRatio < baseline + 0.90 * scale { return .critical }
                return .terminal
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
            /// The state of memory pressure (aka. how close the app is to being jetsammed/jettisoned).
            public let pressure: State

            init(used: Int64, remaining: Int64, compressed: Int64, state: State, pressure: State) {
                self.used = used
                self.remaining = remaining
                self.compressed = compressed
                self.state = state
                self.pressure = pressure
                limit = used + remaining
            }

            /// Convenience init that derives `state` from `(used, used + remaining)`
            /// via `State.from(used:limit:)`. Use this in any provider whose state
            /// policy matches the default; reach for the explicit-state init only
            /// when overriding that policy.
            init(used: Int64, remaining: Int64, compressed: Int64, pressure: State) {
                self.init(
                    used: used,
                    remaining: remaining,
                    compressed: compressed,
                    state: State.from(used: used, limit: used + remaining),
                    pressure: pressure
                )
            }
        }

        /// System-wide memory values independent of the app's memory limit.
        public struct System: Sendable {
            /// Total physical memory on the device.
            public let limit: Int64
            /// Currently available physical memory on the device — truly free
            /// pages (excluding speculative) plus the cached-files bucket
            /// (purgeable + external pages). Matches Activity Monitor's
            /// "Free + Cached Files" view.
            public let remaining: Int64
            /// The state describing the device's memory headroom, derived from
            /// `(used, limit)` with `baseline = 0.80` so only the top ~20% of
            /// the range maps onto warning/urgent/critical/terminal. See
            /// `State.from(used:limit:baseline:)` for the rationale.
            public let state: State

            init(limit: Int64, remaining: Int64, state: State) {
                self.limit = limit
                self.remaining = remaining
                self.state = state
            }

            /// Convenience init that derives `state` from `(used, limit)` with
            /// `baseline = 0.80`. Use this in any provider whose state policy
            /// matches the default; reach for the explicit-state init only when
            /// overriding that policy.
            init(limit: Int64, remaining: Int64) {
                let used = max(limit - remaining, 0)
                self.init(
                    limit: limit,
                    remaining: remaining,
                    state: State.from(used: used, limit: limit, baseline: 0.80)
                )
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
