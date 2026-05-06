//
//  View+Footprint.swift
//  Footprint
//
//  Copyright (c) 2023 Alexander Cohen. All rights reserved.
//

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
        ///         print("Memory state changed from \(oldMemory.app.state) to \(newMemory.app.state)")
        ///         // Perform actions based on the memory change
        ///     }
        @inlinable func onFootprintMemoryDidChange(perform action: @escaping (_ memory: Footprint.Memory, _ previousMemory: Footprint.Memory, _ changes: Set<Footprint.ChangeType>) -> Void) -> some View {
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
                    action(memory.app.state, prevMemory.app.state)
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
                    action(memory.app.pressure, prevMemory.app.pressure)
                }
            }
        }

        @inlinable func onFootprintMemoryHeadroomDidChange(perform action: @escaping (_ headroom: Footprint.Memory.State, _ previousHeadroom: Footprint.Memory.State) -> Void) -> some View {
            _ = Footprint.shared // make sure it's running
            return onReceive(NotificationCenter.default.publisher(for: Footprint.memoryDidChangeNotification)) { note in
                if let changes = note.userInfo?[Footprint.changesKey] as? Set<Footprint.ChangeType>,
                   changes.contains(.headroom),
                   let memory = note.userInfo?[Footprint.newMemoryKey] as? Footprint.Memory,
                   let prevMemory = note.userInfo?[Footprint.oldMemoryKey] as? Footprint.Memory
                {
                    action(memory.system.state, prevMemory.system.state)
                }
            }
        }
    }

#endif
