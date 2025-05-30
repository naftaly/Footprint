# Footprint

[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org/)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-lightgrey.svg)]()

## Overview

Footprint is a Swift library that provides proactive memory management for your Apple platform apps. Instead of waiting for memory warnings that come too late, Footprint gives you real-time insights into your app's memory usage and proximity to termination, allowing you to adapt your app's behavior dynamically.

### The Problem

Traditional memory management on Apple platforms relies on memory warnings that often arrive too late, especially for larger apps. While `os_proc_available_memory` tells you how much memory remains, you still lack the complete picture of your memory boundaries and usage patterns.

### The Solution

Footprint bridges this gap by providing:
- **Complete memory visibility**: Track used, remaining, and total memory limits
- **Proactive state management**: Five distinct memory states from normal to terminal
- **Behavioral adaptation**: Change your app's behavior before hitting critical memory limits
- **Multiple observation patterns**: NotificationCenter, async streams, and SwiftUI modifiers

## Key Features

- **Five Memory States**: Navigate through normal, warning, urgent, critical, and terminal states based on memory usage ratios
- **Dual Tracking**: Monitor both memory footprint and system memory pressure
- **Real-time Monitoring**: 500ms heartbeat with smart change detection
- **SwiftUI Integration**: Convenient view modifiers for reactive UI updates
- **Async Support**: Modern async/await patterns with AsyncStream
- **Cross-platform**: Works on iOS, macOS, tvOS, watchOS, and visionOS

## Installation

Add Footprint to your project using Swift Package Manager:

1. In Xcode, navigate to File > Add Package Dependencies
2. Enter the repository URL:
```
https://github.com/naftaly/Footprint
```

## Usage

### Basic Setup

Initialize Footprint early in your app's lifecycle. The shared instance automatically begins monitoring:

```swift
// Start monitoring (typically in your App or AppDelegate)
let _ = Footprint.shared
```

### Memory State Observation

#### Using NotificationCenter

```swift
NotificationCenter.default.addObserver(
    forName: Footprint.memoryDidChangeNotification, 
    object: nil, 
    queue: nil
) { notification in
    guard let newMemory = notification.userInfo?[Footprint.newMemoryKey] as? Footprint.Memory,
          let oldMemory = notification.userInfo?[Footprint.oldMemoryKey] as? Footprint.Memory,
          let changes = notification.userInfo?[Footprint.changesKey] as? Set<Footprint.ChangeType> 
    else { return }
    
    if changes.contains(.state) {
        print("Memory state changed from \(oldMemory.state) to \(newMemory.state)")
        adaptBehavior(for: newMemory.state)
    }
}
```

#### Using Closures

```swift
Footprint.shared.observe { memory in
    print("Current memory state: \(memory.state)")
    print("Used: \(ByteCountFormatter.string(fromByteCount: memory.used, countStyle: .memory))")
    print("Remaining: \(ByteCountFormatter.string(fromByteCount: memory.remaining, countStyle: .memory))")
}
```

#### Using Async Streams

```swift
Task {
    for await memory in Footprint.shared.memoryStream {
        await handleMemoryChange(memory)
    }
}
```

### SwiftUI Integration

#### Comprehensive Memory Changes

```swift
Text("Memory Status: \(memoryState)")
    .onFootprintMemoryDidChange { newMemory, oldMemory, changes in
        if changes.contains(.state) {
            updateCachePolicy(for: newMemory.state)
        }
        if changes.contains(.pressure) {
            handleMemoryPressure(newMemory.pressure)
        }
    }
```

#### State-Specific Changes

```swift
MyView()
    .onFootprintMemoryStateDidChange { newState, oldState in
        switch newState {
        case .normal:
            enableFullFeatures()
        case .warning:
            reduceCacheSize(by: 0.2)
        case .urgent:
            reduceCacheSize(by: 0.5)
        case .critical:
            clearNonEssentialCaches()
        case .terminal:
            emergencyMemoryCleanup()
        }
    }
```

#### Pressure-Specific Changes

```swift
ContentView()
    .onFootprintMemoryPressureDidChange { newPressure, oldPressure in
        handleSystemMemoryPressure(newPressure)
    }
```

### Memory Information

Access current memory state and information:

```swift
let memory = Footprint.shared.memory

print("Used: \(memory.used) bytes")
print("Remaining: \(memory.remaining) bytes") 
print("Limit: \(memory.limit) bytes")
print("State: \(memory.state)")
print("Pressure: \(memory.pressure)")
print("Timestamp: \(memory.timestamp)")
```

### Memory Allocation Planning

Check if memory allocation is likely to succeed:

```swift
let sizeNeeded: UInt64 = 50_000_000 // 50MB
if Footprint.shared.canAllocate(bytes: sizeNeeded) {
    // Proceed with allocation
    performMemoryIntensiveOperation()
} else {
    // Consider alternatives or cleanup
    cleanupBeforeAllocation()
}
```

## Memory States Explained

Footprint categorizes memory usage into five states based on the ratio of used memory to total limit:

- **Normal** (< 25%): Full functionality, optimal performance
- **Warning** (25-50%): Begin reducing memory usage, optimize caches
- **Urgent** (50-75%): Significant memory reduction needed
- **Critical** (75-90%): Aggressive cleanup required
- **Terminal** (> 90%): Imminent termination risk, emergency measures

## Practical Examples

### Adaptive Cache Management

```swift
class ImageCache {
    private var maxCost: Int = 100_000_000 // 100MB default
    
    init() {
        Footprint.shared.observe { [weak self] memory in
            self?.adjustCacheSize(for: memory.state)
        }
    }
    
    private func adjustCacheSize(for state: Footprint.Memory.State) {
        let multiplier: Double = switch state {
        case .normal: 1.0
        case .warning: 0.8
        case .urgent: 0.5
        case .critical: 0.2
        case .terminal: 0.0
        }
        
        cache.totalCostLimit = Int(Double(maxCost) * multiplier)
    }
}
```

### Conditional Feature Loading

```swift
func loadOptionalFeatures() {
    let currentState = Footprint.shared.state
    
    guard currentState < .urgent else {
        // Skip non-essential features in high memory usage
        return
    }
    
    enableAdvancedAnimations()
    preloadAdditionalContent()
}
```

## Development and Testing

### Simulator Support

Footprint includes simulator-specific handling since memory limits work differently. You can enable simulated termination for testing:

```bash
# Enable simulated out-of-memory termination in simulator
export SIM_FOOTPRINT_OOM_TERM_ENABLED=1
```

### Custom Memory Providers

For testing or custom scenarios, implement the `MemoryProvider` protocol:

```swift
class MockMemoryProvider: MemoryProvider {
    func provide(_ pressure: Footprint.Memory.State) -> Footprint.Memory {
        // Return custom memory values for testing
    }
}
```

## Requirements

- iOS 13.0+, macOS 10.15+, tvOS 13.0+, watchOS 6.0+, visionOS 1.0+
- Swift 5.0+
- Xcode 11.0+

## License

Footprint is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
