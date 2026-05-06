# Footprint

[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org/)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-lightgrey.svg)]()

## Overview

Footprint is a Swift library that provides proactive memory management for your Apple platform apps. Instead of waiting for memory warnings that come too late, Footprint gives you real-time insights into your app's memory usage and proximity to termination, allowing you to adapt your app's behavior dynamically.

### The Problem

Traditional memory management on Apple platforms relies on memory warnings that often arrive too late, especially for larger apps. While `os_proc_available_memory` tells you how much memory remains, you still lack the complete picture of your memory boundaries and usage patterns.

### The Solution

Footprint bridges this gap by providing:
- **Complete memory visibility**: Track app-level used/remaining/limit and device-wide system memory
- **Proactive state management**: Five distinct memory states from normal to terminal
- **Behavioral adaptation**: Change your app's behavior before hitting critical memory limits
- **Multiple observation patterns**: NotificationCenter, async streams, and SwiftUI modifiers

## Key Features

- **Five Memory States**: Navigate through normal, warning, urgent, critical, and terminal states based on memory usage ratios
- **Three Tracking Axes**: App-level state, app-level memory pressure, and system-wide headroom
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
        print("Memory state changed from \(oldMemory.app.state) to \(newMemory.app.state)")
        adaptBehavior(for: newMemory.app.state)
    }
    if changes.contains(.headroom) {
        print("System headroom changed from \(oldMemory.system.state) to \(newMemory.system.state)")
    }
}
```

#### Using Closures

```swift
Footprint.shared.observe { memory in
    print("Current memory state: \(memory.app.state)")
    print("Used: \(ByteCountFormatter.string(fromByteCount: memory.app.used, countStyle: .memory))")
    print("Remaining: \(ByteCountFormatter.string(fromByteCount: memory.app.remaining, countStyle: .memory))")
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
            updateCachePolicy(for: newMemory.app.state)
        }
        if changes.contains(.pressure) {
            handleMemoryPressure(newMemory.app.pressure)
        }
        if changes.contains(.headroom) {
            adaptForSystemHeadroom(newMemory.system.state)
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

#### Headroom-Specific Changes

System-wide headroom (device-level free physical memory) is independent of the
app's own memory limit. Use this to back off when the device is under pressure
even when the app still has room within its own budget.

```swift
ContentView()
    .onFootprintMemoryHeadroomDidChange { newHeadroom, oldHeadroom in
        if newHeadroom >= .urgent {
            pauseBackgroundPrefetch()
        }
    }
```

### Memory Information

Access current memory state and information:

```swift
let memory = Footprint.shared.memory

// App-specific memory (your app's slice).
print("Used: \(memory.app.used) bytes")
print("Remaining: \(memory.app.remaining) bytes")
print("Limit: \(memory.app.limit) bytes")
print("Compressed: \(memory.app.compressed) bytes") // already counted in `used`
print("State: \(memory.app.state)")
print("Pressure: \(memory.app.pressure)")

// System-wide memory (the whole device).
print("System limit: \(memory.system.limit) bytes")
print("System remaining: \(memory.system.remaining) bytes")
print("System state: \(memory.system.state)")

print("Timestamp: \(memory.timestamp)")
```

`Footprint.shared` also exposes `state`, `pressure`, and `headroom` shortcuts
that read directly from the latest snapshot:

```swift
let appState = Footprint.shared.state         // memory.app.state
let appPressure = Footprint.shared.pressure   // memory.app.pressure
let systemHeadroom = Footprint.shared.headroom // memory.system.state
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
            self?.adjustCacheSize(for: memory.app.state)
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

### Code Formatting

This project uses [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) to maintain consistent code style. The Swift version is specified in `.swift-version`.

#### Installing SwiftFormat

```bash
# Using Homebrew
brew install swiftformat
```

#### Running SwiftFormat

```bash
# Format all Swift files in the project
swiftformat .

# Format specific files
swiftformat Sources/Footprint/Footprint.swift

# Check formatting without making changes
swiftformat --lint .
```

The formatter will automatically read the `.swift-version` file to apply the appropriate formatting rules for Swift 6.2.

## Requirements

- iOS 13.0+, macOS 10.15+, tvOS 13.0+, watchOS 6.0+, visionOS 1.0+
- Swift 6.2+
- Xcode 16.4+

## License

Footprint is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
