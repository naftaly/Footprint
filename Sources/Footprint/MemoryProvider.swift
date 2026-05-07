//
//  MemoryProvider.swift
//  Footprint
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
//

import Foundation

/// Source of `Footprint.Memory` snapshots. The default implementation,
/// `Footprint.DefaultMemoryProvider`, reads from the kernel; tests can supply
/// their own. Internal — `Footprint.init(_:)` is also internal, so this
/// protocol is not reachable from outside the module.
///
/// Providers are responsible for *both* the raw byte measurements and the
/// `Memory.App.state` / `Memory.System.state` buckets the measurements map to.
/// Most providers should use `Footprint.Memory.State.from(used:limit:baseline:)`
/// as their default policy — `baseline = 0` (the default) for app state, and
/// `baseline = 0.80` for system state — but they are free to use custom
/// thresholds (e.g. an app-specific OOM tuner or a test fixture that wants
/// deterministic states).
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
protocol MemoryProvider {
    func provide(_ pressure: Footprint.Memory.State) -> Footprint.Memory
}
