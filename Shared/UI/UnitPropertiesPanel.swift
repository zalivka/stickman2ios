import SwiftUI

/// Android UNIT panel — actions for the active scene unit.
struct UnitPropertiesPanel: View {
    static let width: CGFloat = 86
    private static let pane = MainPanel.pane
    private static let label = Color(white: 0.82)

    var unit: StickmanUnit
    var assets: UnitAssets
    var onDeselect: () -> Void
    var onDelete: () -> Void
    var onFlip: () -> Void
    var onDetach: () -> Void
    var onMoveForward: () -> Void
    var onMoveBackward: () -> Void
    var canMoveForward: Bool
    var canMoveBackward: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(unit.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.top, 8)

                Button(action: onDeselect) {
                    Image(decorative: thumb, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                        .frame(width: 56, height: 56)
                        .background(.white)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
                .accessibilityLabel("Deselect \(unit.name)")

                actionButton("Delete", icon: "props_delete", action: onDelete)
                actionButton("Flip", icon: "props_flip", action: onFlip)
                if SlavesRegistry.isEnslaved(unit) {
                    actionButton("Detach", icon: "props_detach", action: onDetach)
                }
                // Android maps “Up” to props_down and “Down” to props_up.
                actionButton(
                    "Up",
                    icon: "props_down",
                    enabled: canMoveForward,
                    action: onMoveForward
                )
                actionButton(
                    "Down",
                    icon: "props_up",
                    enabled: canMoveBackward,
                    action: onMoveBackward
                )
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Self.pane)
    }

    private var thumb: CGImage {
        let stored = assets.archive(for: unit.name)
        return ItemLoader.thumb(from: stored.zip, name: unit.name)
    }

    private func actionButton(
        _ label: String,
        icon: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(decorative: Self.icon(icon), scale: 2)
                    .frame(width: 36, height: 36)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Self.label)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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
            fatalError("UnitPropertiesPanel missing chrome/\(name).png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "chrome/\(name).png")
        } catch {
            fatalError("UnitPropertiesPanel could not read \(url.path): \(error)")
        }
    }
}
