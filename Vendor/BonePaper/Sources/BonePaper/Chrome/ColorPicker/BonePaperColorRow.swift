import SwiftUI
import UIKit

public struct BonePaperColorRow: View {
    @Binding var color: Color

    @State private var extras: [String] = BonePaperColorStore.load()
    @State private var showingPicker = false

    public init(color: Binding<Color>) {
        _color = color
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button {
                showingPicker = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            AngularGradient(
                                colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                center: .center
                            )
                        )
                    Circle()
                        .fill(Color(white: 0.78))
                        .frame(width: 12, height: 12)
                }
                .frame(width: 36, height: 36)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color(white: 0.45), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Color picker")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(swatches, id: \.self) { hex in
                        swatchButton(hex)
                    }
                }
            }
        }
        .frame(height: 36)
        .onReceive(NotificationCenter.default.publisher(for: BonePaperColorStore.didChange)) { _ in
            extras = BonePaperColorStore.load()
        }
        .sheet(isPresented: $showingPicker) {
            BonePaperFlexColorPickerSheet(initial: UIColor(color)) { picked in
                let hex = BonePaperColorStore.hex(from: picked)
                color = BonePaperColorStore.color(from: hex)
                remember(hex)
                showingPicker = false
            }
        }
    }

    private var swatches: [String] {
        extras + BonePaperColorStore.presets
    }

    private func swatchButton(_ hex: String) -> some View {
        let swatch = BonePaperColorStore.color(from: hex)
        let selected = BonePaperColorStore.hex(from: UIColor(color)) == hex
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(swatch)
            .frame(width: 36, height: 36)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color(white: 0.25), lineWidth: 1)
            }
            .overlay {
                if selected {
                    Circle()
                        .strokeBorder(Color.black, lineWidth: 1)
                        .background(Circle().fill(Color.white))
                        .frame(width: 10, height: 10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .onTapGesture {
                color = swatch
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                BonePaperHexToast.show(hex)
            }
            .accessibilityLabel(hex)
            .accessibilityAddTraits(.isButton)
    }

    private func remember(_ hex: String) {
        BonePaperColorStore.remember(hex)
        extras = BonePaperColorStore.load()
    }
}
