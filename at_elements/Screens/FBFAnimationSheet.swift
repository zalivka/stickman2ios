import Combine
import SwiftUI

/// Android `FBFAnimationFragment` — enable, speed, loop; range is caption-only.
struct FBFAnimationSheet: View {
    private static let pane = Color(white: 0.15)
    private static let apply = Color(red: 0x85 / 255, green: 0xb8 / 255, blue: 0x39 / 255)
    private static let previewBox: CGFloat = 200

    let unitName: String
    let scene: StickmanScene
    var assets: UnitAssets
    var existing: FBFAnimation?
    var onCommit: (FBFAnimation?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var draft: FBFAnimation
    @State private var preview: StickmanUnit
    @State private var tick = 0
    @State private var backward = false

    init(
        unitName: String,
        scene: StickmanScene,
        assets: UnitAssets,
        unit: StickmanUnit,
        existing: FBFAnimation?,
        onCommit: @escaping (FBFAnimation?) -> Void
    ) {
        self.unitName = unitName
        self.scene = scene
        self.assets = assets
        self.existing = existing
        self.onCommit = onCommit
        if let existing {
            _enabled = State(initialValue: true)
            _draft = State(initialValue: existing)
        } else {
            _enabled = State(initialValue: false)
            _draft = State(
                initialValue: FBFAnimation(
                    unitname: unitName,
                    loop: false,
                    period: FBFAnimation.minPeriod,
                    startFrameId: FBFAnimation.noRange,
                    endFrameId: FBFAnimation.noRange
                )
            )
        }
        _preview = State(initialValue: Self.fitted(unit, assets: assets))
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                previewColumn
                    .frame(width: geo.size.width / 3)
                controlsColumn
                    .frame(width: geo.size.width * 2 / 3)
            }
        }
        .background(Self.pane)
        .presentationBackground(Self.pane)
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .overlay(alignment: .topLeading) {
            FullscreenBackButton(besideMainPanel: false)
        }
        .onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { _ in
            guard enabled else { return }
            advancePreview()
        }
        .onChange(of: draft.period) { _, _ in
            tick = 0
        }
        .onChange(of: enabled) { _, on in
            tick = 0
            backward = false
            if !on { return }
        }
    }

    private var previewColumn: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            previewCanvas
                .frame(width: side, height: side)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
    }

    private var controlsColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Frame-by-frame animation")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text(rangeCaption)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.72))
                }
                Spacer(minLength: 8)
                Toggle("On", isOn: $enabled)
                    .labelsHidden()
                    .tint(Self.apply)
            }

            if enabled {
                Text("Animation speed \(FBFAnimation.speed(period: draft.period) + 1)")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                Slider(
                    value: speedBinding,
                    in: 0...Double(FBFAnimation.speedMax),
                    step: 1
                )
                .tint(Self.apply)

                Toggle("Loop back and forth", isOn: $draft.loop)
                    .foregroundStyle(.white)
                    .tint(Self.apply)
            }

            Spacer(minLength: 0)

            Button("Apply") {
                onCommit(enabled ? draft : nil)
                dismiss()
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Self.apply)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Self.pane)
    }

    private var previewCanvas: some View {
        SkeletonCanvas(
            unit: $preview,
            frameUnits: [preview],
            assets: assets,
            sceneWidth: Self.previewBox,
            sceneHeight: Self.previewBox,
            sceneFill: .black,
            mode: .preview,
            showSkeleton: false
        )
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var rangeCaption: String {
        let span = draft.toIndices(scene: scene)
        return "animation for frames \(span.start + 1)-\(span.end + 1)"
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { Double(FBFAnimation.speed(period: draft.period)) },
            set: { draft.period = FBFAnimation.period(speed: Int($0.rounded())) }
        )
    }

    private func advancePreview() {
        tick += 1
        if tick % draft.period != 0 { return }
        tick = 0
        let states = assets.states(for: preview.name)
        if states.count < 2 {
            fatalError("FBFAnimationSheet '\(preview.name)' has \(states.count) states")
        }
        let next = preview.nextState(
            states: states,
            current: preview.assetsState,
            backward: backward,
            loop: draft.loop
        )
        backward = next.backward
    }

    private static func fitted(_ unit: StickmanUnit, assets: UnitAssets) -> StickmanUnit {
        var copy = unit
        let box = assets.combinedBounds(for: copy)
        let width = max(box.width, 1)
        let height = max(box.height, 1)
        let pad: CGFloat = 24
        let scale = min((previewBox - pad * 2) / width, (previewBox - pad * 2) / height)
        copy.translateAll(dx: -box.minX, dy: -box.minY)
        copy.scaleBy(pivotX: 0, pivotY: 0, factor: scale)
        copy.translateAll(
            dx: previewBox / 2 - width * scale / 2,
            dy: previewBox / 2 - height * scale / 2
        )
        return copy
    }
}
