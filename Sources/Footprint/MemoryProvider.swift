///
///  MemoryProvider.swift
///  Footprint
///
///  Copyright (c) 2024 Alexander Cohen. All rights reserved.
///

import Foundation

/// Source of `Footprint.Memory` snapshots. The default implementation,
/// `Footprint.DefaultMemoryProvider`, reads from the kernel; tests can supply
/// their own.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
public protocol MemoryProvider {
    func provide(_ pressure: Footprint.Memory.State) -> Footprint.Memory
}
