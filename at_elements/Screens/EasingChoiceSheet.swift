import SwiftUI

struct EasingChoiceSheet: View {
    var initialType: TweenEasing
    var initialStrength: Float
    var initialFrequency: Float
    var showsCartwheel: Bool
    var onApply: (TweenEasing, Float, Float) -> Void

    @State private var easing: TweenEasing
    @State private var strength: Float
    @State private var frequency: Float
    @Environment(\.dismiss) private var dismiss

    private static let pickerOrder: [TweenEasing] = [
        .NO, .IN_OUT_EXPO, .BOUNCE_IN, .BOUNCE_OUT,
        .IN_OUT_BACK, .IN_QUINT, .OUT_QUINT, .SHAKE_X,
        .SHAKE_Y, .CARTWHEEL_CW, .CARTWHEEL_CCW
    ]
    private static let cellSize: CGFloat = 80

    init(
        initialType: TweenEasing,
        initialStrength: Float,
        initialFrequency: Float,
        showsCartwheel: Bool = true,
        onApply: @escaping (TweenEasing, Float, Float) -> Void
    ) {
        self.initialType = initialType
        self.initialStrength = initialStrength
        self.initialFrequency = initialFrequency
        self.showsCartwheel = showsCartwheel
        self.onApply = onApply
        _easing = State(initialValue: initialType)
        _strength = State(initialValue: Self.clampedStrength(initialType, initialStrength))
        _frequency = State(initialValue: UnitTweenStorage.clampFrequency(initialType, initialFrequency))
    }

    var body: some View {
        VStack(spacing: 0) {
            topPanel
            HStack(alignment: .top, spacing: 8) {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                        spacing: 6
                    ) {
                        ForEach(pickerTypes, id: \.self) { type in
                            cell(type)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(alignment: .top, spacing: 8) {
                    if easing != .NO {
                        VerticalValueSlider(value: $strength, range: strengthRange)
                    }
                    if easing.isShake || easing.isCartwheel {
                        VerticalValueSlider(value: $frequency, range: frequencyRange)
                    }
                }
                .frame(width: easing == .NO ? 0 : (easing.isShake || easing.isCartwheel ? 80 : 36))
                .frame(maxHeight: .infinity)
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(SkeletonChrome.pane.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SkeletonChrome.pane)
    }

    private var topPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                backButton
                Text("Tweening")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                applyButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
            SkeletonChrome.bonesAccent.frame(height: 3)
        }
        .background(SkeletonChrome.pane)
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var applyButton: some View {
        Button(action: commit) {
            Text("Apply")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .frame(minWidth: 72)
                .padding(.vertical, 8)
                .background(SkeletonChrome.boneNew)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply")
    }

    private var pickerTypes: [TweenEasing] {
        showsCartwheel ? Self.pickerOrder : Self.pickerOrder.filter { !$0.isCartwheel }
    }

    private func cell(_ type: TweenEasing) -> some View {
        Button {
            select(type)
        } label: {
            VStack(spacing: 2) {
                EasingCurvePreview(
                    easing: type,
                    strength: previewStrength(for: type),
                    frequency: previewFrequency(for: type),
                    selected: type == easing
                )
                .frame(width: Self.cellSize, height: Self.cellSize)
                Text(type.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: Self.cellSize)
                    .frame(minHeight: 20)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ next: TweenEasing) {
        if shouldUseFullStrengthDefault(switchingTo: next) {
            strength = 1
        }
        if !easing.isCartwheel && next.isCartwheel && !initialType.isCartwheel {
            frequency = UnitTweenStorage.defaultCartwheelTurns
            strength = 0
        } else if easing.isShake != next.isShake || easing.isCartwheel != next.isCartwheel {
            frequency = UnitTweenStorage.clampFrequency(next, frequency)
        }
        easing = next
        strength = Self.clampedStrength(next, strength)
        frequency = UnitTweenStorage.clampFrequency(next, frequency)
    }

    private func shouldUseFullStrengthDefault(switchingTo next: TweenEasing) -> Bool {
        if initialType != .NO {
            return false
        }
        if easing != .NO {
            return false
        }
        if next == .NO || next.isShake || next.isCartwheel {
            return false
        }
        return abs(strength - Easing.defaultStrength) < 0.02
    }

    private func previewStrength(for type: TweenEasing) -> Float {
        if type == .NO {
            return 1
        }
        if type == easing {
            return strength
        }
        return type.isCartwheel ? 0 : 1
    }

    private func previewFrequency(for type: TweenEasing) -> Float {
        if type == easing {
            return frequency
        }
        if type.isCartwheel {
            return UnitTweenStorage.defaultCartwheelTurns
        }
        return UnitTweenStorage.defaultShakeFrequency
    }

    private var strengthRange: ClosedRange<Float> {
        easing.isCartwheel ? 0...1 : 0.25...1
    }

    private var frequencyRange: ClosedRange<Float> {
        easing.isCartwheel
            ? UnitTweenStorage.minCartwheelTurns...UnitTweenStorage.maxCartwheelTurns
            : UnitTweenStorage.minShakeFrequency...UnitTweenStorage.maxShakeFrequency
    }

    private func commit() {
        let appliedStrength = easing == .NO ? 1 : strength
        onApply(easing, appliedStrength, UnitTweenStorage.clampFrequency(easing, frequency))
        dismiss()
    }

    private static func clampedStrength(_ type: TweenEasing, _ value: Float) -> Float {
        if type == .NO {
            return 1
        }
        if type.isCartwheel {
            return min(max(value, 0), 1)
        }
        return min(max(value, 0.25), 1)
    }
}

private struct VerticalValueSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let travel = max(height - 22, 1)
            let t = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 4, height: height)
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .offset(y: -(t * travel))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let y = min(max(drag.location.y, 11), height - 11)
                    let nextT = 1 - Float((y - 11) / travel)
                    value = range.lowerBound + nextT * (range.upperBound - range.lowerBound)
                }
            )
        }
        .frame(width: 36)
    }
}

extension TweenEasing {
    var displayName: String {
        switch self {
        case .NO: return "Even speed"
        case .IN_OUT_EXPO: return "Slow–fast–slow"
        case .BOUNCE_IN: return "Bounce at start"
        case .BOUNCE_OUT: return "Bounce at end"
        case .IN_OUT_BACK: return "Overshoot"
        case .IN_QUINT: return "Slow-to-fast"
        case .OUT_QUINT: return "Fast-to-slow"
        case .SHAKE_X: return "Horizontal shake"
        case .SHAKE_Y: return "Vertical shake"
        case .CARTWHEEL_CW: return "Rotation to right"
        case .CARTWHEEL_CCW: return "Rotation to left"
        }
    }

    var chipColor: Color {
        switch self {
        case .NO: return Color(red: 1, green: 0x17 / 255, blue: 0x44 / 255)
        case .IN_OUT_EXPO: return Color(red: 1, green: 0x6d / 255, blue: 0)
        case .BOUNCE_IN: return Color(red: 1, green: 0xab / 255, blue: 0)
        case .BOUNCE_OUT: return Color(red: 0, green: 0xc8 / 255, blue: 0x53 / 255)
        case .IN_OUT_BACK: return Color(red: 0, green: 0xbf / 255, blue: 0xa5 / 255)
        case .IN_QUINT: return Color(red: 0, green: 0xb8 / 255, blue: 0xd4 / 255)
        case .OUT_QUINT: return Color(red: 0x29 / 255, green: 0x79 / 255, blue: 1)
        case .SHAKE_X: return Color(red: 0x65 / 255, green: 0x1f / 255, blue: 1)
        case .SHAKE_Y: return Color(red: 0xd5 / 255, green: 0, blue: 0xf9 / 255)
        case .CARTWHEEL_CW: return Color(red: 0xf5 / 255, green: 0, blue: 0x57 / 255)
        case .CARTWHEEL_CCW: return Color(red: 1, green: 0x3d / 255, blue: 0)
        }
    }
}
