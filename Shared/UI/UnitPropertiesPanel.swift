import SwiftUI
import UIKit

/// Android UNIT panel — actions for the active scene unit.
struct UnitPropertiesPanel: View {
    static let width: CGFloat = 86
    static let effectsWidth: CGFloat = 112
    static let pane = Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255)
    static let accent = Color(red: 0, green: 0xbd / 255, blue: 0x78 / 255)
    private static let label = Color(white: 0.82)
    private static let activeGreen = Color(red: 0x99 / 255, green: 0xc9 / 255, blue: 0x3c / 255)
    private static let effectKinds: [CameraEffect.Kind] = [
        .none, .fade, .desaturate, .colorize
    ]

    var unit: StickmanUnit
    var assets: UnitAssets
    var availableStates: [Int]
    var animationActive: Bool
    var onDeselect: () -> Void
    var onDelete: () -> Void
    var onFlip: () -> Void
    var onDetach: () -> Void
    var onMoveForward: () -> Void
    var onMoveBackward: () -> Void
    var canMoveForward: Bool
    var canMoveBackward: Bool
    var onSelectState: (Int) -> Void
    var onOpenAnimation: () -> Void
    var onCopy: () -> Void
    var onEditItem: (() -> Void)? = nil
    var onSetText: (() -> Void)? = nil
    var poseLocked: Bool = false
    var colorLocked: Bool = false
    var structureOwned: Bool = false
    var tweenEnabled: Bool = true
    var onTween: (() -> Void)? = nil
    var onMore: () -> Void
    var onOpacityDragBegan: () -> Void
    var onOpacityPreview: (CGFloat) -> Void
    /// Returns false when an AUTO interior blocks the write. The live preview stays.
    var onOpacityCommit: (CGFloat) -> Bool
    @Binding var showingEffects: Bool
    var onSelectEffectKind: (CameraEffect.Kind) -> Void = { _ in }
    var onSelectEffectColor: (CameraEffect.Kind, Int) -> Void = { _, _ in }
    var onPickEffectCustomColor: (CameraEffect.Kind, Int) -> Void = { _, _ in }
    var onEffectPowerDragBegan: () -> Void = {}
    var onEffectPowerPreview: (Float) -> Void = { _ in }
    var onEffectPowerCommit: (Float) -> Bool = { _ in true }
    var backTick: Int
    var onClose: () -> Void

    @State private var showingStates = false
    @State private var showingOpacity = false
    @State private var opacityPercent = 100
    @State private var opacityTracking = false
    @State private var effectPercent = 50
    @State private var effectTracking = false
    @State private var showingColorPicker = false
    @State private var pickerKind: CameraEffect.Kind = .fade

    var body: some View {
        HStack(spacing: 0) {
            Self.accent
                .frame(width: 2)
            ZStack {
                actions
                if showingStates {
                    statesOverlay
                }
                if showingOpacity {
                    opacityOverlay
                }
                if showingEffects {
                    effectsOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.pane)
        }
        .frame(width: showingEffects ? Self.effectsWidth : Self.width)
        .frame(maxHeight: .infinity)
        .onChange(of: unit.name) { _, _ in
            showingStates = false
            showingOpacity = false
            showingEffects = false
        }
        .onChange(of: backTick) { _, _ in
            if showingOpacity {
                showingOpacity = false
            } else if showingEffects {
                showingEffects = false
            } else {
                onClose()
            }
        }
        .onChange(of: unit.alpha) { _, alpha in
            if showingOpacity && !opacityTracking {
                opacityPercent = Int(alpha * 100)
            }
        }
        .onChange(of: unit.effect.power) { _, power in
            if showingEffects && !effectTracking {
                effectPercent = Int((power * 100).rounded())
            }
        }
        .sheet(isPresented: $showingColorPicker) {
            FlexColorPickerSheet(initial: pickerInitialColor) { picked in
                if let rgb = AppSettings.rgb(from: picked) {
                    onPickEffectCustomColor(pickerKind, rgb)
                }
                showingColorPicker = false
            }
        }
    }

    private var pickerInitialColor: UIColor {
        if unit.effect.kind == pickerKind && !unit.effect.isZero {
            return AppSettings.uiColor(fromRGB: unit.effect.rgbInt)
        }
        let pal = pickerKind.palette
        let rgb = pal.first ?? 0x000000
        return AppSettings.uiColor(fromRGB: rgb)
    }

    private var actions: some View {
        ScrollView {
            VStack(spacing: 2) {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.top, 8)

                Button(action: onDeselect) {
                    Group {
                        if let thumb {
                            Image(decorative: thumb, scale: 1)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .padding(4)
                    .frame(width: 56, height: 56)
                    .background(.white)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 2)
                .accessibilityLabel("Deselect \(unit.name)")

                if availableStates.count > 1 {
                    actionButton("States", icon: "props_state", enabled: !poseLocked) {
                        showingStates = true
                    }
                }
                if unit.unitType == .bubble {
                    actionButton("Set text", icon: "props_text", enabled: !poseLocked, action: {
                        guard let onSetText else {
                            assertionFailure("UnitPropertiesPanel bubble '\(unit.name)' missing onSetText")
                            return
                        }
                        onSetText()
                    })
                }
                actionButton("Delete", icon: "props_delete", enabled: !poseLocked && !colorLocked, action: onDelete)
                actionButton("Opacity", icon: "props_opacity", enabled: !colorLocked) {
                    opacityPercent = Int(unit.alpha * 100)
                    showingOpacity = true
                }
                actionButton("Effects", icon: "props_effects", enabled: !colorLocked) {
                    effectPercent = Int((unit.effect.power * 100).rounded())
                    showingEffects = true
                }
                actionButton("Flip", icon: "props_flip", enabled: !poseLocked, action: onFlip)
                if SlavesRegistry.isEnslaved(unit) {
                    actionButton("Detach", icon: "props_detach", enabled: !poseLocked && !structureOwned, action: onDetach)
                }
                if let onEditItem {
                    actionButton("Edit", icon: "props_edit_custom", action: onEditItem)
                }
                // Android maps “Up” to props_down and “Down” to props_up.
                actionButton(
                    "Up",
                    icon: "props_down",
                    enabled: canMoveForward && !poseLocked,
                    action: onMoveForward
                )
                actionButton(
                    "Down",
                    icon: "props_up",
                    enabled: canMoveBackward && !poseLocked,
                    action: onMoveBackward
                )
                actionButton("Copy", icon: "props_copy", enabled: !poseLocked, action: onCopy)
                if let onTween {
                    actionButton(
                        structureOwned ? "Tween (AUTO)" : "Tween",
                        icon: "props_tween",
                        enabled: tweenEnabled && !(poseLocked && colorLocked),
                        action: onTween
                    )
                }
                actionButton(
                    "More",
                    icon: "props_numbers",
                    enabled: !poseLocked && !structureOwned,
                    action: onMore
                )
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)
        }
    }

    private var statesOverlay: some View {
        VStack(spacing: 0) {
            Button {
                showingStates = false
            } label: {
                Image(decorative: Self.icon("props_apply"), scale: 2)
                    .frame(width: 45, height: 45)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apply")

            ScrollView {
                VStack(spacing: 0) {
                    if !animationActive {
                        ForEach(availableStates, id: \.self) { state in
                            stateRow(state)
                        }
                    }
                    animateRow
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.pane)
    }

    private var opacityOverlay: some View {
        VStack(spacing: 0) {
            Button {
                showingOpacity = false
            } label: {
                VStack(spacing: 2) {
                    Image(decorative: Self.icon("props_apply"), scale: 2)
                        .frame(width: 45, height: 45)
                    Text("\(opacityPercent)%")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apply")

            VerticalOpacityBar(
                percent: opacityPercent,
                onBegan: {
                    opacityTracking = true
                    onOpacityDragBegan()
                },
                onChanged: { progress in
                    opacityPercent = progress
                    onOpacityPreview(CGFloat(progress) / 100)
                },
                onEnded: {
                    let raw = opacityPercent
                    let snapped = raw < 5 ? 0 : raw
                    let applied = onOpacityCommit(CGFloat(snapped) / 100)
                    opacityPercent = applied ? snapped : raw
                    opacityTracking = false
                }
            )
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.pane)
    }

    private var effectsOverlay: some View {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let displayedPercent = effectTracking ? effectPercent : Int((unit.effect.power * 100).rounded())
        return VStack(spacing: 0) {
            Button {
                showingEffects = false
            } label: {
                VStack(spacing: 2) {
                    Image(decorative: Self.icon("props_apply"), scale: 2)
                        .frame(width: 45, height: 45)
                    if unit.effect.kind != .none {
                        Text("\(displayedPercent)%")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apply")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    VStack(spacing: 6) {
                        ForEach(Self.effectKinds, id: \.self) { kind in
                            effectKindButton(kind)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                    if unit.effect.kind == .fade || unit.effect.kind == .colorize {
                        effectColorGrid
                            .padding(.horizontal, 10)
                            .padding(.top, 2)
                    }
                }
                .padding(.bottom, 8)
            }
            .fixedSize(horizontal: false, vertical: isPad && unit.effect.kind != .none)

            if isPad && unit.effect.kind != .none {
                VerticalOpacityBar(
                    percent: displayedPercent,
                    onBegan: {
                        effectTracking = true
                        effectPercent = Int((unit.effect.power * 100).rounded())
                        onEffectPowerDragBegan()
                    },
                    onChanged: { progress in
                        effectPercent = progress
                        onEffectPowerPreview(Float(progress) / 100.0)
                    },
                    onEnded: {
                        let raw = effectPercent
                        let snapped = raw < 5 ? 0 : raw
                        let applied = onEffectPowerCommit(Float(snapped) / 100.0)
                        effectPercent = applied ? snapped : raw
                        effectTracking = false
                    }
                )
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.pane)
    }

    private func effectKindButton(_ kind: CameraEffect.Kind) -> some View {
        let selected = unit.effect.kind == kind
        return Button {
            onSelectEffectKind(kind)
        } label: {
            Text(kind.displayName)
                .font(.system(size: 14, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.white : Color.white.opacity(0.09))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(colorLocked)
        .opacity(colorLocked ? 0.4 : 1)
        .accessibilityLabel("Item effect \(kind.displayName)")
    }

    private var effectColorGrid: some View {
        let kind = unit.effect.kind
        let palette = kind.palette
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(0..<max(palette.count, 6), id: \.self) { index in
                let rgb = index < palette.count ? palette[index] : 0x000000
                let selected = !unit.effect.isZero && unit.effect.rgbInt == rgb
                Button {
                    onSelectEffectColor(kind, index)
                } label: {
                    Circle()
                        .fill(AppSettings.color(fromRGB: rgb))
                        .frame(width: 24, height: 24)
                        .overlay {
                            Circle()
                                .strokeBorder(selected ? Color.white : Color.clear, lineWidth: 2.5)
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(colorLocked)
                .opacity(colorLocked ? 0.4 : 1)
                .accessibilityLabel("Effect color #\(index + 1) \(AppSettings.hexString(fromRGB: rgb))")
            }

            Button {
                pickerKind = kind
                showingColorPicker = true
            } label: {
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(colorLocked)
            .opacity(colorLocked ? 0.4 : 1)
            .accessibilityLabel("Pick custom color")
        }
    }

    private func stateRow(_ state: Int) -> some View {
        let active = unit.assetsState == state
        return Button {
            onSelectState(state)
        } label: {
            ZStack {
                Image(decorative: Self.icon(active ? "filled_frame" : "empty_frame"), scale: 2)
                    .frame(width: 44, height: 44)
                Text("\(state)")
                    .font(.system(size: 22))
                    .foregroundStyle(active ? Self.activeGreen : .white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("State \(state)")
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private var animateRow: some View {
        Button(action: onOpenAnimation) {
            Image(decorative: Self.icon("animation_cogs"), scale: 2)
                .frame(width: 44, height: 44)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(animationActive ? Self.activeGreen : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Animate")
    }

    private var caption: String {
        if poseLocked || structureOwned {
            return "\(unit.name) [AUTO]"
        }
        return unit.name
    }

    private var thumb: CGImage? {
        guard let stored = assets.archive(for: unit.name) else {
            return nil
        }
        return ThumbCache.imageIfPresent("props:" + unit.name) {
            try ItemLoader.thumb(from: stored.zip, name: unit.name)
        }
    }

    private func actionButton(
        _ label: String,
        icon: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                let image = Self.icon(icon)
                Image(decorative: image, scale: CGFloat(image.width) / 45)
                    .frame(width: 45, height: 45)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Self.label)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private static func icon(_ name: String) -> CGImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        else {
            // bundled resource: a failure here ships broken, fires on first debug run
            fatalError("UnitPropertiesPanel missing chrome/\(name).png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "chrome/\(name).png")
        } catch {
            // bundled resource: a failure here ships broken, fires on first debug run
            fatalError("UnitPropertiesPanel could not read \(url.path): \(error)")
        }
    }
}

/// Android `VerticalSeekBar`: 100 at the top, 0 at the bottom.
private struct VerticalOpacityBar: UIViewRepresentable {
    var percent: Int
    var onBegan: () -> Void
    var onChanged: (Int) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> OpacityBarView {
        let view = OpacityBarView()
        view.percent = percent
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateUIView(_ view: OpacityBarView, context: Context) {
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.percent = percent
    }
}

private final class OpacityBarView: UIView {
    var percent: Int = 100 {
        didSet {
            if percent != oldValue {
                setNeedsDisplay()
            }
        }
    }
    var onBegan: () -> Void = {}
    var onChanged: (Int) -> Void = { _ in }
    var onEnded: () -> Void = {}

    private let inset: CGFloat = 11

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        let press = UILongPressGestureRecognizer(target: self, action: #selector(press(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        addGestureRecognizer(press)
    }

    required init?(coder: NSCoder) {
        // unused: views are built in code; storyboard init is never invoked
        fatalError("OpacityBarView init(coder:) is unused")
    }

    override func draw(_ rect: CGRect) {
        let travel = max(bounds.height - inset * 2, 1)
        let thumbY = inset + CGFloat(100 - percent) / 100 * travel
        let track = UIBezierPath(
            roundedRect: CGRect(x: bounds.midX - 2, y: inset, width: 4, height: travel),
            cornerRadius: 2
        )
        UIColor.white.withAlphaComponent(0.28).setFill()
        track.fill()
        let thumb = UIBezierPath(ovalIn: CGRect(x: bounds.midX - 11, y: thumbY - 11, width: 22, height: 22))
        UIColor.white.setFill()
        thumb.fill()
    }

    @objc private func press(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            onBegan()
            apply(gesture.location(in: self).y)
        case .changed:
            apply(gesture.location(in: self).y)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    private func apply(_ y: CGFloat) {
        let travel = max(bounds.height - inset * 2, 1)
        let clamped = min(max(y, inset), inset + travel)
        let progress = max(0, 100 - Int((clamped - inset) / travel * 100))
        percent = progress
        onChanged(progress)
    }
}
