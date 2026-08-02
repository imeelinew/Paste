import AppKit
import Foundation

@main
@MainActor
struct ActivationPolicyTests {
    static func main() {
        var states: [Bool] = []
        let coordinator = ActivationPolicyCoordinator { states.append($0) }

        coordinator.acquire("settings")
        coordinator.acquire("about")
        coordinator.release("settings")
        coordinator.release("about")
        expect(
            states == [true, true, true, false],
            "overlapping windows keep regular activation until the final close")

        states.removeAll()
        coordinator.acquire("about")
        coordinator.acquire("about")
        coordinator.release("about")
        expect(states == [true, true, false], "reopening one lease cannot strand the Dock icon")

        states.removeAll()
        coordinator.acquire("settings")
        coordinator.reset()
        expect(states == [true, false], "reset restores accessory activation")

        print("3/3 passed")
    }

    static func expect(_ condition: Bool, _ label: String) {
        guard condition else {
            print("FAIL: \(label)")
            exit(1)
        }
    }
}
