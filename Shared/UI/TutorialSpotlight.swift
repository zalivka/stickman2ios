import SwiftUI
import UIKit

/// Bounds of the control the tutorial hint points at. Read by `overlayPreferenceValue`.
struct TutorialHoleKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() {
            value = next
        }
    }
}

extension View {
    func tutorialHole(_ active: Bool) -> some View {
        anchorPreference(key: TutorialHoleKey.self, value: .bounds) { (anchor: Anchor<CGRect>) -> Anchor<CGRect>? in
            active ? anchor : nil
        }
    }
}

/// Android `FullscreenHint` with `setDismissOnlyOnHoleTap(true)`: dim with a round hole over
/// `target`, text in the middle. Swallows every touch; a tap inside the hole calls `onTargetTap`.
struct TutorialSpotlight: View {
    let target: CGRect
    let text: Text
    let onTargetTap: () -> Void

    @State private var holeShrunk = false
    @State private var dimShown = false

    var body: some View {
        let radius: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 80 : 60
        let center = CGPoint(x: target.midX, y: target.midY)
        let hole = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ZStack {
            TutorialRoundHole(center: center, radius: holeShrunk ? radius : radius * 2)
                .fill(Color.black.opacity(Self.dimAlpha), style: FillStyle(eoFill: true))
                .opacity(dimShown ? 1 : 0)
            text
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(15)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { (value: SpatialTapGesture.Value) in
                if hole.contains(value.location) {
                    onTargetTap()
                }
            }
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                holeShrunk = true
            }
            withAnimation(.easeOut(duration: 1.0)) {
                dimShown = true
            }
        }
    }

    /// Android `FullscreenHint.mDimAlpha` 140 of 255.
    private static let dimAlpha: Double = 140.0 / 255.0
}

private struct TutorialRoundHole: Shape {
    var center: CGPoint
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        return path
    }
}