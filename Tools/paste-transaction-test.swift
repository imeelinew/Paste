import Foundation

@main
@MainActor
struct PasteTransactionTests {
    static var failures = 0
    static var passes = 0

    static func main() async {
        await permissionFailureHasNoSideEffects()
        await preparationFailureHasNoSideEffects()
        await targetFailureDoesNotWrite()
        await deliveryFailureDoesNotCommit()
        await successUsesDeterministicOrder()
        await cancellationBeforeDeliveryHasNoSideEffects()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func permissionFailureHasNoSideEffects() async {
        var events: [String] = []
        let success = await run(events: &events, permission: false)
        expect(!success && events == ["permission"], "permission failure stops before preparation")
    }

    static func preparationFailureHasNoSideEffects() async {
        var events: [String] = []
        let success = await run(events: &events, payload: nil)
        expect(
            !success && events == ["permission", "prepare"],
            "missing payload does not hide, activate, or mutate")
    }

    static func targetFailureDoesNotWrite() async {
        var events: [String] = []
        let success = await run(events: &events, targetReady: false)
        expect(
            !success && events == ["permission", "prepare", "willDeliver", "target"],
            "a dead target never changes the pasteboard")
    }

    static func deliveryFailureDoesNotCommit() async {
        var events: [String] = []
        let success = await run(events: &events, delivered: false)
        expect(
            !success
                && events
                    == ["permission", "prepare", "willDeliver", "target", "write", "deliver"],
            "a failed event delivery never promotes history")
    }

    static func successUsesDeterministicOrder() async {
        var events: [String] = []
        let success = await run(events: &events)
        expect(
            success
                && events
                    == [
                        "permission", "prepare", "willDeliver", "target", "write", "deliver",
                        "commit",
                    ],
            "a successful paste commits only after delivery")
    }

    static func cancellationBeforeDeliveryHasNoSideEffects() async {
        let recorder = Recorder([])
        let task = Task { @MainActor in
            await PasteTransaction.run {
                recorder.append("permission")
                return true
            } prepare: {
                recorder.append("prepare")
                try? await Task.sleep(for: .milliseconds(50))
                return "payload"
            } willDeliver: {
                recorder.append("willDeliver")
            } targetReady: {
                recorder.append("target")
                return true
            } write: { _ in
                recorder.append("write")
                return true
            } deliver: {
                recorder.append("deliver")
                return true
            } commit: {
                recorder.append("commit")
            }
        }
        await Task.yield()
        task.cancel()
        let success = await task.value
        expect(
            !success && recorder.events == ["permission", "prepare"],
            "cancelling preparation cannot hide or mutate")
    }

    static func run(
        events: inout [String], permission: Bool = true, payload: String? = "payload",
        targetReady: Bool = true, delivered: Bool = true
    ) async -> Bool {
        // The transaction is actor-isolated, so this pointer remains scoped to one deterministic
        // test invocation while allowing each escaping closure to record its stage.
        let recorder = Recorder(events)
        let success = await PasteTransaction.run {
            recorder.append("permission")
            return permission
        } prepare: {
            recorder.append("prepare")
            return payload
        } willDeliver: {
            recorder.append("willDeliver")
        } targetReady: {
            recorder.append("target")
            return targetReady
        } write: { _ in
            recorder.append("write")
            return true
        } deliver: {
            recorder.append("deliver")
            return delivered
        } commit: {
            recorder.append("commit")
        }
        events = recorder.events
        return success
    }

    final class Recorder {
        var events: [String]
        init(_ events: [String]) { self.events = events }
        func append(_ event: String) { events.append(event) }
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            print("FAIL: \(label)")
            failures += 1
        }
    }
}
