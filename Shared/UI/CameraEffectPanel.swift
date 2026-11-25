import SwiftUI
import UIKit

struct CameraEffectPanel: View {
    static let width: CGFloat = 112
    static let pane = Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255)
    static let accent = MainPanel.cameraEffects
    private static let effectKinds: [CameraEffect.Kind] = [
        .none, .fade, .desaturate, .colorize
    ]

    var effect: CameraEffect
    var locked: Bool
    var onSelectKind: (CameraEffect.Kind) -> Void
    var onSelectColor: (CameraEffect.Kind, Int) -> Void
    var onPickCustomColor: (CameraEffect.Kind, Int, Int) -> Void

    private var activeKind: CameraEffect.Kind {
        effect.kind == .fade || effect.kind == .colorize ? effect.kind : (effect.kind == .desaturate ? .desaturate : .none)
    }

    private var showsPalette: Bool {
        effect.kind == .fade || effect.kind == .colorize
    }

    var body: some View {
        HStack(spacing: 0) {
            Self.accent
                .frame(width: 2)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    Text("EFFECT")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(white: 0.72))
                        .padding(.top, 10)

                    VStack(spacing: 6) {
                        ForEach(Self.effectKinds, id: \.self) { kind in
                            kindButton(kind)
                        }
                    }
                    .padding(.horizontal, 8)

                    if showsPalette {
                        colorGrid
                            .padding(.horizontal, 10)
                            .padding(.top, 4)
                    }
                }
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.pane)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .sheet(isPresented: $showingColorPicker) {
            FlexColorPickerSheet(initial: pickerInitialColor) { picked in
                if let rgb = AppSettings.rgb(from: picked) {
                    let kind = pickerKind
                    let slot = effect.colorIndex >= 0 ? effect.colorIndex : 0
                    onPickCustomColor(kind, slot, rgb)
                }
                showingColorPicker = false
            }
        }
    }

    @State private var showingColorPicker = false
    @State private var pickerKind: CameraEffect.Kind = .fade

    private var pickerInitialColor: UIColor {
        let pal = pickerKind.palette
        let idx = effect.colorIndex >= 0 ? effect.colorIndex : 0
        let clamped = min(max(idx, 0), max(pal.count - 1, 0))
        let rgb = pal.isEmpty ? 0x000000 : pal[clamped]
        return AppSettings.uiColor(fromRGB: rgb)
    }

    private func kindButton(_ kind: CameraEffect.Kind) -> some View {
        let selected = effect.kind == kind
        return Button {
            onSelectKind(kind)
        } label: {
            Text(kind.displayName)
                .font(.system(size: 14, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Self.accent : Color.white.opacity(0.09))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.4 : 1)
        .accessibilityLabel("Camera effect \(kind.displayName)")
    }

    private var colorGrid: some View {
        let kind = effect.kind
        let palette = kind.palette
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(0..<max(palette.count, 6), id: \.self) { index in
                let rgb = index < palette.count ? palette[index] : 0x000000
                let selected = effect.colorIndex == index
                Button {
                    onSelectColor(kind, index)
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
                .disabled(locked)
                .opacity(locked ? 0.4 : 1)
                .accessibilityLabel("Effect color #\(index + 1) \(AppSettings.hexString(fromRGB: rgb))")
            }

            // "+" cell: pick any color and write it into the selected slot.
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
            .disabled(locked)
            .opacity(locked ? 0.4 : 1)
            .accessibilityLabel("Pick custom color")
        }
    }
}

struct CameraEffectPowerBar: View {
    var effect: CameraEffect
    var locked: Bool
    var onPowerDragBegan: () -> Void
    var onPowerChanged: (Float) -> Void
    var onPowerEnded: () -> Void

    @State private var trackingPower = false
    @State private var powerPercent: Int = 50

    var body: some View {
        HorizontalEffectPowerBar(
            percent: displayedPercent,
            enabled: !locked,
            onBegan: {
                trackingPower = true
                powerPercent = Int((effect.power * 100).rounded())
                onPowerDragBegan()
            },
            onChanged: { next in
                powerPercent = next
                onPowerChanged(Float(next) / 100.0)
            },
            onEnded: {
                trackingPower = false
                onPowerEnded()
            }
        )
        .frame(maxWidth: 260)
        .frame(height: 32)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(CameraEffectPanel.pane.opacity(0.94))
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .onChange(of: effect.power) { _, newValue in
            if !trackingPower {
                powerPercent = Int((newValue * 100).rounded())
            }
        }
        .onAppear {
            powerPercent = Int((effect.power * 100).rounded())
        }
    }

    private var displayedPercent: Int {
        trackingPower ? powerPercent : Int((effect.power * 100).rounded())
    }
}

private struct HorizontalEffectPowerBar: UIViewRepresentable {
    var percent: Int
    var enabled: Bool
    var onBegan: () -> Void
    var onChanged: (Int) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> HorizontalPowerBarView {
        let view = HorizontalPowerBarView()
        view.percent = percent
        view.isUserInteractionEnabled = enabled
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateUIView(_ view: HorizontalPowerBarView, context: Context) {
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.isUserInteractionEnabled = enabled
        view.alpha = enabled ? 1.0 : 0.4
        view.percent = percent
    }
}

private final class HorizontalPowerBarView: UIView {
    var percent: Int = 50 {
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
        fatalError("HorizontalPowerBarView init(coder:) is unused")
    }

    override func draw(_ rect: CGRect) {
        let travel = max(bounds.width - inset * 2, 1)
        let clamped = min(max(percent, 0), 100)
        let thumbX = inset + CGFloat(clamped) / 100 * travel
        let track = UIBezierPath(
            roundedRect: CGRect(x: inset, y: bounds.midY - 2, width: travel, height: 4),
            cornerRadius: 2
        )
        UIColor.white.withAlphaComponent(0.28).setFill()
        track.fill()

        let activeWidth = max(thumbX - inset, 0)
        if activeWidth > 0 {
            let active = UIBezierPath(
                roundedRect: CGRect(x: inset, y: bounds.midY - 2, width: activeWidth, height: 4),
                cornerRadius: 2
            )
            UIColor(red: 1, green: 0x2E / 255, blue: 0x93 / 255, alpha: 1).setFill()
            active.fill()
        }

        let r: CGFloat = 9
        let thumb = UIBezierPath(
            ovalIn: CGRect(x: thumbX - r, y: bounds.midY - r, width: r * 2, height: r * 2)
        )
        UIColor(red: 1, green: 0x2E / 255, blue: 0x93 / 255, alpha: 1).setFill()
        thumb.fill()
    }

    @objc private func press(_ gr: UILongPressGestureRecognizer) {
        switch gr.state {
        case .began:
            onBegan()
            scrub(to: gr.location(in: self).x)
        case .changed:
            scrub(to: gr.location(in: self).x)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    private func scrub(to x: CGFloat) {
        let travel = max(bounds.width - inset * 2, 1)
        let t = min(max((x - inset) / travel, 0), 1)
        onChanged(Int((t * 100).rounded()))
    }
}
