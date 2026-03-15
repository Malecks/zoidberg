import Cocoa

final class EscapeKeyMonitor {
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var holdTimer: Timer?
    private var isHolding = false
    private var didTriggerHold = false

    var onTap: (() -> Void)?
    var onHold: (() -> Void)?
    var onHoldStart: (() -> Void)?
    var onHoldCancel: (() -> Void)?
    var holdDuration: TimeInterval = 1.5

    func start() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            // Consume the event (return nil) to prevent system beep
            if !event.isARepeat {
                self?.startHold()
            }
            return nil
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.endHold()
            return nil
        }
    }

    private func startHold() {
        guard !isHolding else { return }
        isHolding = true
        didTriggerHold = false
        onHoldStart?()
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
            self?.didTriggerHold = true
            self?.isHolding = false
            self?.onHold?()
        }
    }

    private func endHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        if isHolding && !didTriggerHold {
            onHoldCancel?()
            onTap?()
        }
        isHolding = false
        didTriggerHold = false
    }

    func stop() {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m) }
        keyDownMonitor = nil
        keyUpMonitor = nil
        holdTimer?.invalidate()
        holdTimer = nil
    }

    deinit {
        stop()
    }
}
