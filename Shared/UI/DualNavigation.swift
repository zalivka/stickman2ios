enum DualNavigation {
    enum Mode {
        case frames
        case range
    }

    static func pinToFrame(pin: Int, frameCount: Int) -> Int {
        preconditionIndex(pin, frameCount: frameCount, label: "pin")
        return frameCount - 1 - pin
    }

    static func frameToPin(frame: Int, frameCount: Int) -> Int {
        preconditionIndex(frame, frameCount: frameCount, label: "frame")
        return frameCount - 1 - frame
    }

    static func defaultRange(current: Int, frameCount: Int) -> ClosedRange<Int> {
        preconditionIndex(current, frameCount: frameCount, label: "current")
        if frameCount < 1 {
            fatalError("DualNavigation frameCount must be >= 1, got \(frameCount)")
        }
        let last = frameCount - 1
        if current == last {
            return max(0, last - 12)...last
        }
        return current...min(current + 12, last)
    }

    private static func preconditionIndex(_ index: Int, frameCount: Int, label: String) {
        if frameCount < 1 {
            fatalError("DualNavigation frameCount must be >= 1, got \(frameCount)")
        }
        if index < 0 || index >= frameCount {
            fatalError("DualNavigation \(label) \(index) out of range 0..<\(frameCount)")
        }
    }
}
