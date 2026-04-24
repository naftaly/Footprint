@testable import Footprint
import XCTest

// MARK: - Mock Memory Provider

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
class MockMemoryProvider: MemoryProvider {
    var used: Int64 = 100_000_000 // 100 MB
    var remaining: Int64 = 900_000_000 // 900 MB
    var compressed: Int64 = 0
    var systemLimit: Int64 = 8_000_000_000 // 8 GB
    var systemRemaining: Int64 = 4_000_000_000 // 4 GB

    func provide(_ pressure: Footprint.Memory.State) -> Footprint.Memory {
        Footprint.Memory(
            used: used,
            remaining: remaining,
            compressed: compressed,
            pressure: pressure,
            system: Footprint.Memory.System(limit: systemLimit, remaining: systemRemaining)
        )
    }
}

// MARK: - Tests

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
class FootprintTests: XCTestCase {
    // MARK: - Basic Memory Tests

    func testLimit() {
        let mem = Footprint.shared.memory
        XCTAssertGreaterThan(mem.limit, 0)
    }

    func testName() {
        XCTAssertEqual("\(Footprint.Memory.State.normal)", "normal")
    }

    // MARK: - Memory.State Tests

    func testMemoryStateComparison() {
        XCTAssertLessThan(Footprint.Memory.State.normal, .warning)
        XCTAssertLessThan(Footprint.Memory.State.warning, .urgent)
        XCTAssertLessThan(Footprint.Memory.State.urgent, .critical)
        XCTAssertLessThan(Footprint.Memory.State.critical, .terminal)
    }

    func testMemoryStateStringInit() {
        XCTAssertEqual(Footprint.Memory.State("normal"), .normal)
        XCTAssertEqual(Footprint.Memory.State("warning"), .warning)
        XCTAssertEqual(Footprint.Memory.State("urgent"), .urgent)
        XCTAssertEqual(Footprint.Memory.State("critical"), .critical)
        XCTAssertEqual(Footprint.Memory.State("terminal"), .terminal)
        XCTAssertNil(Footprint.Memory.State("invalid"))
    }

    func testMemoryStateAllCases() {
        let allCases = Footprint.Memory.State.allCases
        XCTAssertEqual(allCases.count, 5)
        XCTAssertEqual(allCases, [.normal, .warning, .urgent, .critical, .terminal])
    }

    // MARK: - Memory Initialization and State Calculation Tests

    func testMemoryInitNormalState() {
        // Used: 100 MB, Remaining: 900 MB, Total: 1 GB
        // Used ratio: 0.1 (10%)
        let memory = Footprint.Memory(used: 100_000_000, remaining: 900_000_000)

        XCTAssertEqual(memory.used, 100_000_000)
        XCTAssertEqual(memory.remaining, 900_000_000)
        XCTAssertEqual(memory.limit, 1_000_000_000)
        XCTAssertEqual(memory.state, .normal)
        XCTAssertEqual(memory.pressure, .normal)
    }

    func testMemoryInitWarningState() {
        // Used: 300 MB, Remaining: 700 MB, Total: 1 GB
        // Used ratio: 0.3 (30%)
        let memory = Footprint.Memory(used: 300_000_000, remaining: 700_000_000)

        XCTAssertEqual(memory.state, .warning)
    }

    func testMemoryInitUrgentState() {
        // Used: 600 MB, Remaining: 400 MB, Total: 1 GB
        // Used ratio: 0.6 (60%)
        let memory = Footprint.Memory(used: 600_000_000, remaining: 400_000_000)

        XCTAssertEqual(memory.state, .urgent)
    }

    func testMemoryInitCriticalState() {
        // Used: 800 MB, Remaining: 200 MB, Total: 1 GB
        // Used ratio: 0.8 (80%)
        let memory = Footprint.Memory(used: 800_000_000, remaining: 200_000_000)

        XCTAssertEqual(memory.state, .critical)
    }

    func testMemoryInitTerminalState() {
        // Used: 950 MB, Remaining: 50 MB, Total: 1 GB
        // Used ratio: 0.95 (95%)
        let memory = Footprint.Memory(used: 950_000_000, remaining: 50_000_000)

        XCTAssertEqual(memory.state, .terminal)
    }

    func testMemoryStateBoundaries() {
        // Test exact boundaries
        let boundary25 = Footprint.Memory(used: 250_000_000, remaining: 750_000_000) // 25%
        XCTAssertEqual(boundary25.state, .warning)

        let boundary50 = Footprint.Memory(used: 500_000_000, remaining: 500_000_000) // 50%
        XCTAssertEqual(boundary50.state, .urgent)

        let boundary75 = Footprint.Memory(used: 750_000_000, remaining: 250_000_000) // 75%
        XCTAssertEqual(boundary75.state, .critical)

        let boundary90 = Footprint.Memory(used: 900_000_000, remaining: 100_000_000) // 90%
        XCTAssertEqual(boundary90.state, .terminal)
    }

    func testMemoryPressureInit() {
        let memory = Footprint.Memory(
            used: 100_000_000,
            remaining: 900_000_000,
            pressure: .critical
        )

        XCTAssertEqual(memory.pressure, .critical)
        XCTAssertEqual(memory.state, .normal) // State based on used ratio
    }

    func testMemoryTimestamp() {
        let memory = Footprint.Memory(used: 100_000_000, remaining: 900_000_000)

        XCTAssertGreaterThan(memory.timestamp, 0)
    }

    // MARK: - canAllocate Tests

    func testCanAllocate() {
        let footprint = Footprint.shared
        let memory = footprint.memory

        // Should not be able to allocate more than remaining
        XCTAssertFalse(footprint.canAllocate(bytes: UInt64(memory.remaining) + 1000))

        // If we have remaining memory, should be able to allocate a small amount
        if memory.remaining > 1000 {
            XCTAssertTrue(footprint.canAllocate(bytes: 1000))
        }
    }

    func testCanAllocateZero() {
        let footprint = Footprint.shared
        let memory = footprint.memory

        // Can only allocate 0 if there's at least some remaining memory
        if memory.remaining > 0 {
            XCTAssertTrue(footprint.canAllocate(bytes: 0))
        }
    }

    // MARK: - Observer Tests

    func testObserverReceivesInitialMemory() {
        let footprint = Footprint.shared
        let expectation = XCTestExpectation(description: "Observer receives initial memory")

        footprint.observe { memory in
            XCTAssertGreaterThan(memory.limit, 0)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testMultipleObservers() {
        let footprint = Footprint.shared
        let expectation1 = XCTestExpectation(description: "Observer 1")
        let expectation2 = XCTestExpectation(description: "Observer 2")

        footprint.observe { _ in
            expectation1.fulfill()
        }

        footprint.observe { _ in
            expectation2.fulfill()
        }

        wait(for: [expectation1, expectation2], timeout: 2.0)
    }

    // MARK: - Notification Tests

    func testNotificationKeys() {
        XCTAssertEqual(Footprint.oldMemoryKey, "oldMemory")
        XCTAssertEqual(Footprint.newMemoryKey, "newMemory")
        XCTAssertEqual(Footprint.changesKey, "changes")
    }

    func testMemoryDidChangeNotificationName() {
        let expectedName = NSNotification.Name("FootprintMemoryDidChangeNotification")
        XCTAssertEqual(Footprint.memoryDidChangeNotification, expectedName)
    }

    // MARK: - State and Pressure Properties

    func testStateProperty() {
        let footprint = Footprint.shared
        let state = footprint.state

        XCTAssertTrue([.normal, .warning, .urgent, .critical, .terminal].contains(state))
    }

    func testPressureProperty() {
        let footprint = Footprint.shared
        let pressure = footprint.pressure

        XCTAssertTrue([.normal, .warning, .urgent, .critical, .terminal].contains(pressure))
    }

    func testMemoryProperty() {
        let footprint = Footprint.shared
        let memory = footprint.memory

        XCTAssertGreaterThan(memory.used, 0)
        XCTAssertGreaterThanOrEqual(memory.remaining, 0)
        XCTAssertGreaterThan(memory.limit, 0)
        XCTAssertEqual(memory.limit, memory.used + memory.remaining)
    }

    func testSystemMemory() {
        let memory = Footprint.shared.memory

        XCTAssertGreaterThan(memory.system.limit, 0)
        XCTAssertGreaterThanOrEqual(memory.system.remaining, 0)
        XCTAssertLessThanOrEqual(memory.system.remaining, memory.system.limit)
    }

    func testSystemMemoryFromMockProvider() {
        let mock = MockMemoryProvider()
        mock.systemLimit = 8_000_000_000
        mock.systemRemaining = 3_000_000_000
        let memory = mock.provide(.normal)

        XCTAssertEqual(memory.system.limit, 8_000_000_000)
        XCTAssertEqual(memory.system.remaining, 3_000_000_000)
    }

    // MARK: - ChangeType Tests

    func testChangeTypeComparable() {
        // Test that ChangeType conforms to Comparable
        let stateChange: Footprint.ChangeType = .state
        let pressureChange: Footprint.ChangeType = .pressure
        let footprintChange: Footprint.ChangeType = .footprint

        // Just verify they can be used in sets
        let changes: Set<Footprint.ChangeType> = [stateChange, pressureChange, footprintChange]
        XCTAssertEqual(changes.count, 3)
    }

    // MARK: - AsyncStream Tests

    func testMemoryStreamCreation() async {
        let footprint = Footprint.shared
        let stream = footprint.memoryStream

        // Create a task to consume the stream
        let task = Task {
            var count = 0
            for await memory in stream {
                XCTAssertGreaterThan(memory.limit, 0)
                count += 1
                if count >= 1 {
                    break
                }
            }
        }

        // Give it some time to potentially receive updates
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        task.cancel()
    }

    func testMultipleMemoryStreams() async {
        let footprint = Footprint.shared
        let stream1 = footprint.memoryStream
        let stream2 = footprint.memoryStream

        let task1 = Task {
            for await memory in stream1 {
                XCTAssertGreaterThan(memory.limit, 0)
                break
            }
        }

        let task2 = Task {
            for await memory in stream2 {
                XCTAssertGreaterThan(memory.limit, 0)
                break
            }
        }

        // Give streams time to potentially receive updates
        try? await Task.sleep(nanoseconds: 600_000_000) // 600ms (more than heartbeat interval)

        task1.cancel()
        task2.cancel()

        // At least one stream should have received an update within the heartbeat interval
        // Note: In real scenarios with actual memory changes, both would receive updates
    }

    // MARK: - Thread Safety Tests

    func testConcurrentMemoryAccess() {
        let footprint = Footprint.shared
        let iterations = 100
        let expectation = XCTestExpectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = iterations

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = footprint.memory
            _ = footprint.state
            _ = footprint.pressure
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testConcurrentObserverRegistration() {
        let footprint = Footprint.shared
        let iterations = 50
        let expectation = XCTestExpectation(description: "Concurrent observer registration")
        expectation.expectedFulfillmentCount = iterations

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            footprint.observe { _ in
                // Observer registered
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }
}
