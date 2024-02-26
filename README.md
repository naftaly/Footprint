# Footprint

[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org/)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-lightgrey.svg)]()

## Overview

Footprint is a Swift library that helps manage and monitor memory usage in your app. It provides a flexible approach to handling memory levels, allowing you to adapt your app's behavior based on the available memory and potential termination risks.

### Key Features

- **Memory State Management:** Footprint categorizes memory states into normal, warning, critical, and terminal, providing insights into your app's proximity to termination due to memory constraints.

- **Dynamic Memory Handling:** Change your app's behavior dynamically based on the current memory state. For instance, adjust cache sizes or optimize resource usage to enhance performance.

- **SwiftUI Integration:** Easily observe and respond to changes in the app's memory state within SwiftUI views using the `onFootprintMemoryStateDidChange` modifier.

## Installation

Add the Footprint library to your project:

1. In Xcode, with your app project open, navigate to File > Add Packages.
2. When prompted, add the Firebase Apple platforms SDK repository:
```
https://github.com/naftaly/Footprint
```

## Usage

### Initialization

Initialize Footprint as early as possible in your app's lifecycle:

```swift
let _ = Footprint.shared
```

### Memory State Observation

Respond to changes in memory state using the provided notification:

```swift
NotificationCenter.default.addObserver(forName: Footprint.stateDidChangeNotification, object: nil, queue: nil) { notification in
    if let newState = notification.userInfo?[Footprint.newMemoryStateKey] as? Footprint.Memory.State,
       let oldState = notification.userInfo?[Footprint.oldMemoryStateKey] as? Footprint.Memory.State {
        print("Memory state changed from \(oldState) to \(newState)")
        // Perform actions based on the memory state change
    }
}
```

### SwiftUI Integration

Use the SwiftUI extension to observe changes in memory state within your views:

```swift
Text("Hello, World!")
    .onFootprintMemoryStateDidChange { newState, oldState in
        print("Memory state changed from \(oldState) to \(newState)")
        // Perform actions based on the memory state change
    }
```

### Memory Information Retrieval

Retrieve current memory information:

```swift
let currentMemory = footprint.memory
print("Used Memory: \(currentMemory.used) bytes")
print("Remaining Memory: \(currentMemory.remaining) bytes")
print("Memory Limit: \(currentMemory.limit) bytes")
print("Memory State: \(currentMemory.state)")
```

### Memory Allocation Check

Check if a certain amount of memory can be allocated:

```swift
let canAllocate = footprint.canAllocate(bytes: 1024)
print("Can allocate 1KB: \(canAllocate)")
```

## License

Footprint is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
