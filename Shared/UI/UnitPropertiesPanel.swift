import SwiftUI

/// Android UNIT panel — actions for the active scene unit.
struct UnitPropertiesPanel: View {
    static let width: CGFloat = 86
    static let pane = Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255)
    static let accent = Color(red: 0, green: 0xbd / 255, blue: 0x78 / 255)
    private static let label = Color(white: 0.82)
    private static let activeGreen = Color(red: 0x99 / 255, green: 0xc9 / 255, blue: 0x3c / 255)

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
    var onSetText: (() -> Void)? = nil
    var poseLocked: Bool = false
    var structureOwned: Bool = false
    var tweenEnabled: Bool = true
    var onTween: (() -> Void)? = nil
    var onClose: () -> Void

    @State private var showingStates = false

    var body: some View {
        HStack(spacing: 0) {
            Self.accent
                .frame(width: 2)
            ZStack {
                actions
                if showingStates {
                    statesOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.pane)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            BackCircleButton(action: onClose)
                .padding(.leading, 8)
                .padding(.top, 8)
        }
        .onChange(of: unit.name) { _, _ in
            showingStates = false
        }
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
                    .padding(.top, Self.listTop)

                Button(action: onDeselect) {
                    Image(decorative: thumb, scale: 1)
                        .resizable()
                        .scaledToFit()
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
                            fatalError("UnitPropertiesPanel bubble '\(unit.name)' missing onSetText")
                        }
                        onSetText()
                    })
                }
                actionButton("Delete", icon: "props_delete", enabled: !poseLocked, action: onDelete)
                actionButton("Flip", icon: "props_flip", enabled: !poseLocked, action: onFlip)
                if SlavesRegistry.isEnslaved(unit) {
                    actionButton("Detach", icon: "props_detach", enabled: !poseLocked && !structureOwned, action: onDetach)
                }
                if let onTween {
                    actionButton(
                        structureOwned ? "Tween (AUTO)" : "Tween",
                        icon: "props_tween",
                        enabled: tweenEnabled && !poseLocked && !structureOwned,
                        action: onTween
                    )
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
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)
        }
    }

    private var statesOverlay: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.listTop)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.pane)
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

    /// Clears the pinned Back control. 8 top inset + 44 circle + 8 gap.
    private static let listTop: CGFloat = 60

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
            fatalError("UnitPropertiesPanel missing chrome/\(name).png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "chrome/\(name).png")
        } catch {
            fatalError("UnitPropertiesPanel could not read \(url.path): \(error)")
        }
    }
}
