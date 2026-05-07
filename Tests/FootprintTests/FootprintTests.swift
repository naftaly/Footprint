@testable import Footprint
import XCTest

// MARK: - Mock Memory Provider

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
class MockMemoryProvider: MemoryProvider {
    // Lock-guarded so tests can mutate from one thread while Footprint's
    // heartbeat queue reads from another (Thread Sanitizer flags the
    // unsynchronized version).
    private let _lock = NSLock()
    private var _used: Int64 = 100_000_000 // 100 MB
    private var _remaining: Int64 = 900_000_000 // 900 MB
    private var _compressed: Int64 = 0
    private var _systemLimit: Int64 = 8_000_000_000 // 8 GB
    private var _systemRemaining: Int64 = 4_000_000_000 // 4 GB

    var used: Int64 {
        get { _lock.withLock { _used } }
        set { _lock.withLock { _used = newValue } }
    }

    var remaining: Int64 {
        get { _lock.withLock { _remaining } }
        set { _lock.withLock { _remaining = newValue } }
    }

    var compressed: Int64 {
        get { _lock.withLock { _compressed } }
        set { _lock.withLock { _compressed = newValue } }
    }

    var systemLimit: Int64 {
        get { _lock.withLock { _systemLimit } }
        set { _lock.withLock { _systemLimit = newValue } }
    }

    var systemRemaining: Int64 {
        get { _lock.withLock { _systemRemaining } }
        set { _lock.withLock { _systemRemaining = newValue } }
    }

    func provide(_ pressure: Footprint.Memory.State) -> Footprint.Memory {
        _lock.withLock {
            Footprint.Memory(
                app: Footprint.Memory.App(
                    used: _used,
                    remaining: _remaining,
                    compressed: _compressed,
                    pressure: pressure
                ),
                system: Footprint.Memory.System(
                    limit: _systemLimit,
                    remaining: _systemRemaining
                )
            )
        }
    }
}

// MARK: - Tests

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
class FootprintTests: XCTestCase {
    // MARK: - Basic Memory Tests

    func testLimit() {
        let mem = Footprint.shared.memory
        XCTAssertGreaterThan(mem.app.limit, 0)
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

    // MARK: - App Initialization and State Calculation Tests

    private func makeApp(
        used: Int64,
        remaining: Int64,
        pressure: Footprint.Memory.State = .normal
    ) -> Footprint.Memory.App {
        Footprint.Memory.App(
            used: used,
            remaining: remaining,
            compressed: 0,
            pressure: pressure
        )
    }

    private func makeSystem(
        limit: Int64,
        remaining: Int64
    ) -> Footprint.Memory.System {
        Footprint.Memory.System(limit: limit, remaining: remaining)
    }

    func testAppInitNormalState() {
        // Used: 100 MB, Remaining: 900 MB, Total: 1 GB
        // Used ratio: 0.1 (10%)
        let app = makeApp(used: 100_000_000, remaining: 900_000_000)

        XCTAssertEqual(app.used, 100_000_000)
        XCTAssertEqual(app.remaining, 900_000_000)
        XCTAssertEqual(app.limit, 1_000_000_000)
        XCTAssertEqual(app.state, .normal)
        XCTAssertEqual(app.pressure, .normal)
    }

    func testAppInitWarningState() {
        // Used: 300 MB, Remaining: 700 MB, Total: 1 GB
        // Used ratio: 0.3 (30%)
        let app = makeApp(used: 300_000_000, remaining: 700_000_000)

        XCTAssertEqual(app.state, .warning)
    }

    func testAppInitUrgentState() {
        // Used: 600 MB, Remaining: 400 MB, Total: 1 GB
        // Used ratio: 0.6 (60%)
        let app = makeApp(used: 600_000_000, remaining: 400_000_000)

        XCTAssertEqual(app.state, .urgent)
    }

    func testAppInitCriticalState() {
        // Used: 800 MB, Remaining: 200 MB, Total: 1 GB
        // Used ratio: 0.8 (80%)
        let app = makeApp(used: 800_000_000, remaining: 200_000_000)

        XCTAssertEqual(app.state, .critical)
    }

    func testAppInitTerminalState() {
        // Used: 950 MB, Remaining: 50 MB, Total: 1 GB
        // Used ratio: 0.95 (95%)
        let app = makeApp(used: 950_000_000, remaining: 50_000_000)

        XCTAssertEqual(app.state, .terminal)
    }

    func testAppStateBoundaries() {
        // Test exact boundaries
        let boundary25 = makeApp(used: 250_000_000, remaining: 750_000_000) // 25%
        XCTAssertEqual(boundary25.state, .warning)

        let boundary50 = makeApp(used: 500_000_000, remaining: 500_000_000) // 50%
        XCTAssertEqual(boundary50.state, .urgent)

        let boundary75 = makeApp(used: 750_000_000, remaining: 250_000_000) // 75%
        XCTAssertEqual(boundary75.state, .critical)

        let boundary90 = makeApp(used: 900_000_000, remaining: 100_000_000) // 90%
        XCTAssertEqual(boundary90.state, .terminal)
    }

    func testAppPressureInit() {
        let app = makeApp(used: 100_000_000, remaining: 900_000_000, pressure: .critical)

        XCTAssertEqual(app.pressure, .critical)
        XCTAssertEqual(app.state, .normal) // State based on used ratio
    }

    func testAppCompressed() {
        // `compressed` is a public, informational field; pages are also counted in `used`.
        let app = Footprint.Memory.App(
            used: 500_000_000,
            remaining: 500_000_000,
            compressed: 80_000_000,
            state: .urgent,
            pressure: .normal
        )

        XCTAssertEqual(app.compressed, 80_000_000)
        XCTAssertEqual(app.used, 500_000_000) // unchanged by compressed
    }

    func testMemoryTimestamp() {
        let memory = Footprint.Memory(
            app: makeApp(used: 100_000_000, remaining: 900_000_000),
            system: makeSystem(limit: 0, remaining: 0)
        )

        XCTAssertGreaterThan(memory.timestamp, 0)
    }

    // MARK: - canAllocate Tests

    func testCanAllocate() {
        let footprint = Footprint.shared
        let memory = footprint.memory

        // Should not be able to allocate more than remaining
        XCTAssertFalse(footprint.canAllocate(bytes: UInt64(memory.app.remaining) + 1000))

        // If we have remaining memory, should be able to allocate a small amount
        if memory.app.remaining > 1000 {
            XCTAssertTrue(footprint.canAllocate(bytes: 1000))
        }
    }

    func testCanAllocateZero() {
        let footprint = Footprint.shared
        let memory = footprint.memory

        // Can only allocate 0 if there's at least some remaining memory
        if memory.app.remaining > 0 {
            XCTAssertTrue(footprint.canAllocate(bytes: 0))
        }
    }

    // MARK: - Observer Tests

    func testObserverReceivesInitialMemory() {
        let footprint = Footprint.shared
        let expectation = XCTestExpectation(description: "Observer receives initial memory")

        footprint.observe { memory in
            XCTAssertGreaterThan(memory.app.limit, 0)
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

    func testHeadroomProperty() {
        let footprint = Footprint.shared
        let headroom = footprint.headroom

        XCTAssertTrue([.normal, .warning, .urgent, .critical, .terminal].contains(headroom))
        XCTAssertEqual(headroom, footprint.memory.system.state)
    }

    func testMemoryProperty() {
        let footprint = Footprint.shared
        let memory = footprint.memory

        XCTAssertGreaterThan(memory.app.used, 0)
        XCTAssertGreaterThanOrEqual(memory.app.remaining, 0)
        XCTAssertGreaterThan(memory.app.limit, 0)
        XCTAssertEqual(memory.app.limit, memory.app.used + memory.app.remaining)
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

    // MARK: - System State Tests

    func testStateFromUsedAndLimit() {
        XCTAssertEqual(Footprint.Memory.State.from(used: 100, limit: 1000), .normal) // 10%
        XCTAssertEqual(Footprint.Memory.State.from(used: 300, limit: 1000), .warning) // 30%
        XCTAssertEqual(Footprint.Memory.State.from(used: 600, limit: 1000), .urgent) // 60%
        XCTAssertEqual(Footprint.Memory.State.from(used: 800, limit: 1000), .critical) // 80%
        XCTAssertEqual(Footprint.Memory.State.from(used: 950, limit: 1000), .terminal) // 95%
    }

    func testStateFromZeroLimit() {
        XCTAssertEqual(Footprint.Memory.State.from(used: 0, limit: 0), .normal)
        XCTAssertEqual(Footprint.Memory.State.from(used: 100, limit: 0), .normal)
    }

    // System state uses the same 25/50/75/90 ladder as App but shifted by
    // baseline = 0.80, so only the top ~20% of physical memory maps onto
    // warning/urgent/critical/terminal. The remaining-percentage boundaries
    // for System are 15% / 10% / 5% / 2%.

    func testStateFromUsedAndLimitWithBaseline() {
        // baseline = 0.80 shifts the 25/50/75/90 thresholds to 85/90/95/98.
        XCTAssertEqual(Footprint.Memory.State.from(used: 800, limit: 1000, baseline: 0.80), .normal) // 80%
        XCTAssertEqual(Footprint.Memory.State.from(used: 840, limit: 1000, baseline: 0.80), .normal) // 84%
        XCTAssertEqual(Footprint.Memory.State.from(used: 870, limit: 1000, baseline: 0.80), .warning) // 87%
        XCTAssertEqual(Footprint.Memory.State.from(used: 920, limit: 1000, baseline: 0.80), .urgent) // 92%
        XCTAssertEqual(Footprint.Memory.State.from(used: 960, limit: 1000, baseline: 0.80), .critical) // 96%
        XCTAssertEqual(Footprint.Memory.State.from(used: 990, limit: 1000, baseline: 0.80), .terminal) // 99%
    }

    func testSystemMemoryStateNormalWhenAmpleHeadroom() {
        // 7 GB free of 8 GB → 87.5% remaining, well above the 15% normal floor.
        let system = makeSystem(limit: 8_000_000_000, remaining: 7_000_000_000)
        XCTAssertEqual(system.state, .normal)
    }

    func testSystemMemoryStateWarning() {
        // 1 GB free of 8 GB → 12.5% remaining, in the 10–15% warning band.
        let system = makeSystem(limit: 8_000_000_000, remaining: 1_000_000_000)
        XCTAssertEqual(system.state, .warning)
    }

    func testSystemMemoryStateUrgent() {
        // 600 MB free of 8 GB → 7.5% remaining, in the 5–10% urgent band.
        let system = makeSystem(limit: 8_000_000_000, remaining: 600_000_000)
        XCTAssertEqual(system.state, .urgent)
    }

    func testSystemMemoryStateCritical() {
        // 300 MB free of 8 GB → 3.75% remaining, in the 2–5% critical band.
        let system = makeSystem(limit: 8_000_000_000, remaining: 300_000_000)
        XCTAssertEqual(system.state, .critical)
    }

    func testSystemMemoryStateTerminal() {
        // 100 MB free of 8 GB → 1.25% remaining, below the 2% terminal floor.
        let system = makeSystem(limit: 8_000_000_000, remaining: 100_000_000)
        XCTAssertEqual(system.state, .terminal)
    }

    func testSystemMemoryStateLargeDeviceIdleStillNormal() {
        // 11 GB free on a 16 GB device — 68.75% remaining, still well above
        // the 15% normal floor. Sanity check that baselining keeps idle
        // large-RAM devices out of the danger zone.
        let system = makeSystem(limit: 16_000_000_000, remaining: 11_000_000_000)
        XCTAssertEqual(system.state, .normal)
    }

    func testSystemMemoryStateZeroLimit() {
        // limit == 0 has no meaningful state to derive; the formula returns
        // .normal rather than treating it as terminal.
        let system = makeSystem(limit: 0, remaining: 0)
        XCTAssertEqual(system.state, .normal)
    }

    // MARK: - ChangeType Tests

    func testChangeTypeComparable() {
        // Test that ChangeType conforms to Comparable
        let stateChange: Footprint.ChangeType = .state
        let pressureChange: Footprint.ChangeType = .pressure
        let headroomChange: Footprint.ChangeType = .headroom
        let footprintChange: Footprint.ChangeType = .footprint

        // Just verify they can be used in sets
        let changes: Set<Footprint.ChangeType> = [stateChange, pressureChange, headroomChange, footprintChange]
        XCTAssertEqual(changes.count, 4)
    }

    // MARK: - Headroom Notification Flow

    // MARK: - Available System Bytes

    // Matches Activity Monitor's "Free + Cached Files" view:
    //   (free_count - speculative_count) + purgeable_count + external_page_count

    func testAvailableSystemBytesSumsFreeAndCached() {
        var stats = vm_statistics64_data_t()
        stats.free_count = 100
        stats.purgeable_count = 30
        stats.external_page_count = 20

        let bytes = Footprint.DefaultMemoryProvider.availableSystemBytes(from: stats, pageSize: 16_384)

        XCTAssertEqual(bytes, Int64(150) * 16_384)
    }

    func testAvailableSystemBytesSubtractsSpeculativeFromFree() {
        // speculative_count is a subset of free_count; Activity Monitor's
        // displayed "Free" subtracts it because speculative pages may be
        // evicted shortly.
        var stats = vm_statistics64_data_t()
        stats.free_count = 100
        stats.speculative_count = 40

        let bytes = Footprint.DefaultMemoryProvider.availableSystemBytes(from: stats, pageSize: 4_096)

        XCTAssertEqual(bytes, Int64(60) * 4_096)
    }

    func testAvailableSystemBytesIgnoresInactiveAndInUsePages() {
        // Active, wired, compressor, and inactive pages are not added by
        // this formula. File-backed inactive pages re-enter the count via
        // external_page_count; anonymous inactive pages would require
        // compression or swap to reclaim, which is what we want headroom
        // transitions to warn us *before*.
        var stats = vm_statistics64_data_t()
        stats.free_count = 10
        stats.inactive_count = 20
        stats.active_count = 2_000
        stats.wire_count = 3_000
        stats.compressor_page_count = 4_000

        let bytes = Footprint.DefaultMemoryProvider.availableSystemBytes(from: stats, pageSize: 4_096)

        XCTAssertEqual(bytes, Int64(10) * 4_096)
    }

    // MARK: - Lifecycle

    func testFootprintDeallocationDoesNotTrap() {
        // Regression: deinit used to suspend each dispatch source before
        // cancelling, which traps in libdispatch when the source is then
        // released. Repeated construct-and-release should be safe.
        for _ in 0 ..< 50 {
            _ = Footprint(MockMemoryProvider())
        }
    }

    func testHeadroomChangeFiresNotification() {
        let mock = MockMemoryProvider()
        mock.systemLimit = 8_000_000_000
        mock.systemRemaining = 7_000_000_000 // ~12.5% used → .normal

        let footprint = Footprint(mock)

        // Wait for the initial observer callback to confirm Footprint has
        // latched the starting `.normal` system state. Relying on a fixed
        // sleep is racy because the timer's leeway can push the first
        // heartbeat out by up to 500ms.
        let initialLatched = XCTestExpectation(description: "initial memory snapshot delivered")
        footprint.observe { _ in initialLatched.fulfill() }
        wait(for: [initialLatched], timeout: 2.0)

        let expect = XCTestExpectation(description: "memoryDidChangeNotification fires with .headroom")
        expect.assertForOverFulfill = false

        let token = NotificationCenter.default.addObserver(
            forName: Footprint.memoryDidChangeNotification,
            object: nil,
            queue: nil
        ) { note in
            // Filter to our mock's notifications - the limit+remaining combo
            // is unique to this test.
            guard let changes = note.userInfo?[Footprint.changesKey] as? Set<Footprint.ChangeType>,
                  let memory = note.userInfo?[Footprint.newMemoryKey] as? Footprint.Memory,
                  let prevMemory = note.userInfo?[Footprint.oldMemoryKey] as? Footprint.Memory,
                  memory.system.limit == 8_000_000_000,
                  memory.system.remaining == 100_000_000
            else { return }

            XCTAssertTrue(changes.contains(.headroom))
            XCTAssertTrue(changes.contains(.footprint))
            XCTAssertEqual(prevMemory.system.state, .normal)
            XCTAssertEqual(memory.system.state, .terminal)
            expect.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        // Drop free memory below the 2% terminal floor (100 MB / 8 GB ≈ 1.25%).
        mock.systemRemaining = 100_000_000

        wait(for: [expect], timeout: 3.0)
        _ = footprint // keep alive until the notification arrives
    }

    // MARK: - AsyncStream Tests

    func testMemoryStreamCreation() async {
        let footprint = Footprint.shared
        let stream = footprint.memoryStream

        // Create a task to consume the stream
        let task = Task {
            var count = 0
            for await memory in stream {
                XCTAssertGreaterThan(memory.app.limit, 0)
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
                XCTAssertGreaterThan(memory.app.limit, 0)
                break
            }
        }

        let task2 = Task {
            for await memory in stream2 {
                XCTAssertGreaterThan(memory.app.limit, 0)
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
