///
///  DefaultMemoryProvider.swift
///  Footprint
///
///  Copyright (c) 2024 Alexander Cohen. All rights reserved.
///

import Foundation

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
extension Footprint {
    class DefaultMemoryProvider: MemoryProvider {

        func provide(_ pressure: Footprint.Memory.State = .normal) -> Footprint.Memory {

            var info = task_vm_info_data_t()
            var infoCount = TASK_VM_INFO_COUNT

            let kerr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, thread_flavor_t(TASK_VM_INFO), $0, &infoCount)
                }
            }
            let used: Int64 = kerr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
            let compressed: Int64 = kerr == KERN_SUCCESS ? Int64(info.compressed) : 0
            #if targetEnvironment(simulator)
            // In the simulator `limit_bytes_remaining` returns -1
            // which means we can't calculate limits.
            // Due to this, we just set it to 4GB.
            let limit: Int64 = 6_000_000_000
            let remaining: Int64 = max(limit - used, 0)
            #else
            let remaining: Int64 = kerr == KERN_SUCCESS ? Int64(info.limit_bytes_remaining) : 0
            #endif
            return Footprint.Memory(
                used: used,
                remaining: remaining,
                compressed: compressed,
                pressure: pressure
            )
        }

        private let TASK_BASIC_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_basic_info_data_t>.size / MemoryLayout<UInt32>.size)
        private let TASK_VM_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<UInt32>.size)
    }
}
