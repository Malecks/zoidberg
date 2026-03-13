import Cocoa

final class EscapeKeyMonitor {
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var holdTimer: Timer?
    private var didTriggerHold = false

    var onTap: (() -> Void)?
    var onHold: (() -> Void)?
    var holdDuration: TimeInterval = 1.5

    func start() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, !event.isARepeat else { return event }
            self?.handleKeyDown()
            return nil
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.handleKeyUp()
            return nil
        }
    }

    func stop() {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m) }
        keyDownMonitor = nil
        keyUpMonitor = nil
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func handleKeyDown() {
        didTriggerHold = false
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
            self?.didTriggerHold = true
            self?.onHold?()
        }
    }

    private func handleKeyUp() {
        holdTimer?.invalidate()
        holdTimer = nil
        if !didTriggerHold {
            onTap?()
        }
        didTriggerHold = false
    }

    deinit {
        stop()
    }
}
