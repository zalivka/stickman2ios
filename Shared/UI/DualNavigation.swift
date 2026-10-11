enum DualNavigation {
    enum Mode {
        case frames
        case range
    }

    static func pinToFrame(pin: Int, frameCount: Int) -> Int {
        let pin = clampedIndex(pin, frameCount: frameCount)
        return frameCount - 1 - pin
    }

    static func frameToPin(frame: Int, frameCount: Int) -> Int {
        let frame = clampedIndex(frame, frameCount: frameCount)
        return frameCount - 1 - frame
    }

    static func defaultRange(current: Int, frameCount: Int) -> ClosedRange<Int> {
        guard frameCount >= 1 else {
            return 0...0
        }
        let current = clampedIndex(current, frameCount: frameCount)
        let last = frameCount - 1
        if current == last {
            return max(0, last - 12)...last
        }
        return current...min(current + 12, last)
    }

    // Called from render paths where the bound index can momentarily outrun a
    // shrinking frame count; clamp instead of trap.
    private static func clampedIndex(_ index: Int, frameCount: Int) -> Int {
        min(max(index, 0), frameCount - 1)
    }
}
