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
            var infoCount = Self.TASK_VM_INFO_COUNT

            let kerr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    task_info(mach_task_self_, thread_flavor_t(TASK_VM_INFO), $0, &infoCount)
                }
            }
            let used: Int64 = kerr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
            let compressed: Int64 = kerr == KERN_SUCCESS ? Int64(info.compressed) : 0
            #if targetEnvironment(simulator)
            // In the simulator `limit_bytes_remaining` returns -1
            // which means we can't calculate limits. We pick 3GB so that
            // memory-pressure scenarios are actually reachable while
            // exercising tests in the simulator.
            let limit: Int64 = 3_000_000_000
            let remaining: Int64 = max(limit - used, 0)
            #else
            let remaining: Int64 = kerr == KERN_SUCCESS ? Int64(info.limit_bytes_remaining) : 0
            #endif

            var vmStats = vm_statistics64_data_t()
            var vmInfoCount = Self.HOST_VM_INFO64_COUNT
            let vmKerr = withUnsafeMutablePointer(to: &vmStats) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmInfoCount)) {
                    host_statistics64(Self.hostPort, HOST_VM_INFO64, $0, &vmInfoCount)
                }
            }
            // Inactive pages still hold data, but the kernel can reclaim them
            // without paging out, so we treat them as available system headroom
            // alongside truly free pages.
            let availablePages = UInt64(vmStats.free_count) + UInt64(vmStats.inactive_count)
            let systemRemaining: Int64 = vmKerr == KERN_SUCCESS ? Int64(availablePages * Self.pageSize) : 0

            return Footprint.Memory(
                app: Footprint.Memory.App(used: used, remaining: remaining, compressed: compressed, pressure: pressure),
                system: Footprint.Memory.System(limit: Self.systemLimit, remaining: systemRemaining)
            )
        }

        // All process-lifetime constants — page size and physical memory
        // are fixed at kernel boot, and the mach_msg counts are derived
        // from compile-time type sizes. The host port send right is
        // cached for the lifetime of the process; pairing it with a
        // mach_port_deallocate would invalidate the cached value for
        // anything else holding it.
        private static let hostPort: host_t = mach_host_self()
        private static let pageSize: UInt64 = UInt64(getpagesize())
        private static let systemLimit: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)

        private static let TASK_VM_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<UInt32>.size)
        private static let HOST_VM_INFO64_COUNT = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<UInt32>.size)
    }
}
