import SwiftUI
import UIKit

enum SkeletonToolsPanel {
    case none
    case bones
    case draw
}

enum SkeletonChrome {
    static let sidebarWidth: CGFloat = 75
    static let secondaryWidth: CGFloat = 80
    static let pane = Color(red: 0x24 / 255, green: 0x25 / 255, blue: 0x30 / 255)
    static let bonesAccent = Color(red: 0xFC / 255, green: 0x96 / 255, blue: 0x1F / 255)
    static let drawAccent = Color(red: 0x2F / 255, green: 0x88 / 255, blue: 0xFF / 255)
    static let toggleIdle = Color(white: 0x66 / 255)
    static let stripeWidth: CGFloat = 4
    static let toolLabel = Color(red: 0x82 / 255, green: 0x82 / 255, blue: 0x82 / 255)
    static let boneNew = Color(red: 0x99 / 255, green: 0xc9 / 255, blue: 0x3c / 255)
    static let boneNewPressed = Color(red: 0x4a / 255, green: 0x6b / 255, blue: 0x18 / 255)
    static let holdBanner = Color(red: 1, green: 0xaf / 255, blue: 0x3b / 255)
    static let galleryPhoneWidth: CGFloat = 100
    static let galleryPadWidth: CGFloat = 180
    static let galleryRowHeight: CGFloat = 80
    /// Gallery bone cells — white at 30% over the canvas (rail itself is clear).
    static let galleryThumbFill = Color.white.opacity(0.3)
    static let galleryHighlight = Color.red
    /// NEW BONE fill — opaque bright blue; label stays white.
    static let galleryNewBone = Color(red: 0, green: 0xB2 / 255, blue: 1)

    static func galleryWidth(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        horizontalSizeClass == .regular ? galleryPadWidth : galleryPhoneWidth
    }

    static func leadingWidth(panel: SkeletonToolsPanel) -> CGFloat {
        sidebarWidth + (panel == .none ? 0 : secondaryWidth)
    }
}

struct SkeletonBackButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

struct SkeletonPreviewPanel: View {
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            SkeletonBackButton(action: onBack)
        }
        .frame(width: SkeletonChrome.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(SkeletonChrome.pane)
    }
}

struct SkeletonLeftPanel: View {
    var panel: SkeletonToolsPanel
    var onMenu: () -> Void
    var onSelect: (SkeletonToolsPanel) -> Void
    var menuActivated: Bool
    var editEnabled: Bool
    var onEdit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onMenu) {
                Image(decorative: Self.navIcon, scale: UIScreen.main.scale)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(menuActivated ? Color(white: 0.22) : Color.clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Menu")
            .padding(.top, 8)
            .padding(.horizontal, 8)

            VStack(spacing: 12) {
                toggle("BONES", accent: SkeletonChrome.bonesAccent, selected: panel == .bones) {
                    onSelect(panel == .bones ? .none : .bones)
                }
                VStack(spacing: 8) {
                    toggle("DRAW", accent: SkeletonChrome.drawAccent, selected: panel == .draw) {
                        onSelect(panel == .draw ? .none : .draw)
                    }
                    editButton
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 0)

            undoButton
        }
        .frame(width: SkeletonChrome.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(SkeletonChrome.pane)
    }

    private var editButton: some View {
        Button(action: onEdit) {
            VStack(spacing: 2) {
                Image(decorative: Self.editIcon, scale: 3)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                Text("Edit")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .opacity(editEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!editEnabled)
        .accessibilityLabel("Edit")
    }

    private var undoButton: some View {
        Image(decorative: Self.undoIcon, scale: 3)
            .resizable()
            .scaledToFit()
            .frame(width: 36, height: 36)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .accessibilityLabel("Undo")
    }

    private func toggle(_ title: String, accent: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 19)
                .background(selected ? accent : SkeletonChrome.toggleIdle)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 2,
                    bottomLeadingRadius: 2,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                ))
        }
        .buttonStyle(.plain)
    }

    private static let navIcon: CGImage = chromeImage("main_btn_nav")
    private static let editIcon: CGImage = chromeImage("skel_edit_draw")
    private static let undoIcon: CGImage = chromeImage("skel_btn_undo")
}

struct SkeletonSecondaryPanel: View {
    var accent: Color
    var content: SkeletonSecondaryContent = .empty

    var body: some View {
        HStack(spacing: 0) {
            accent.frame(width: SkeletonChrome.stripeWidth)
            Group {
                switch content {
                case .empty:
                    SkeletonChrome.pane
                case .bones(let onBoneHoldStart, let onBoneHoldEnd, let onDelete, let onMoveDown, let onMoveUp):
                    SkeletonBonesTools(
                        onBoneHoldStart: onBoneHoldStart,
                        onBoneHoldEnd: onBoneHoldEnd,
                        onDelete: onDelete,
                        onMoveDown: onMoveDown,
                        onMoveUp: onMoveUp
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SkeletonChrome.pane)
        }
        .frame(width: SkeletonChrome.secondaryWidth)
        .frame(maxHeight: .infinity)
    }
}

enum SkeletonSecondaryContent {
    case empty
    case bones(
        onBoneHoldStart: () -> Void,
        onBoneHoldEnd: () -> Void,
        onDelete: () -> Void,
        onMoveDown: () -> Void,
        onMoveUp: () -> Void
    )
}

/// Android `skeleton_node_tools`: New (hold), Props, Delete, Down, Up.
struct SkeletonBonesTools: View {
    var onBoneHoldStart: () -> Void
    var onBoneHoldEnd: () -> Void
    var onDelete: () -> Void
    var onMoveDown: () -> Void
    var onMoveUp: () -> Void
    @State private var newPressed = false

    var body: some View {
        VStack(spacing: 0) {
            boneNewButton
            toolButton(title: "Props", icon: "skel_edit_point_active", action: {})
            toolButton(title: "Delete", icon: "skel_btn_del_active", action: onDelete)
            toolButton(title: "Down", icon: "bone_down_active", action: onMoveDown)
            toolButton(title: "Up", icon: "bone_up_active", action: onMoveUp)
        }
        .padding(.top, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var boneNewButton: some View {
        ZStack {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(newPressed ? SkeletonChrome.boneNewPressed : SkeletonChrome.boneNew)
                        .frame(width: 48, height: 48)
                    Image(decorative: Self.plusIcon, scale: UIScreen.main.scale)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                }
                Text("NEW")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SkeletonChrome.toolLabel)
                    .textCase(.uppercase)
            }
            // Must sit above the artwork — a .background UIView loses most hits to SwiftUI.
            HoldTouchPad(
                onBegan: {
                    newPressed = true
                    onBoneHoldStart()
                },
                onEnded: {
                    newPressed = false
                    onBoneHoldEnd()
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel("Hold to add a bone")
    }

    private func toolButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(decorative: Self.icon(icon), scale: 3)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SkeletonChrome.toolLabel)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let plusIcon: CGImage = chromeImage("plus_icon")

    private static func icon(_ name: String) -> CGImage {
        chromeImage(name)
    }
}

struct SkeletonSideMenu: View {
    var onPick: () -> Void
    var onSaveAs: () -> Void
    var onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("Save as", icon: "square.and.arrow.down", action: onSaveAs)
            row("Preview", icon: "eye", action: onPreview)
            row("Audio", icon: "speaker.wave.2", action: onPick)
            row("Settings", icon: "gearshape", action: onPick)
            row("Help", icon: "questionmark.circle", action: onPick)
            Spacer(minLength: 0)
        }
        .frame(width: SideMenu.width)
        .frame(maxHeight: .infinity)
        .background(SkeletonChrome.pane)
    }

    private func row(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 26)
                Text(title)
                    .font(.system(size: 20))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(white: 0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func chromeImage(_ name: String) -> CGImage {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "chrome")
        ?? Bundle.main.url(forResource: name, withExtension: "png")
    else {
        fatalError("chrome missing \(name).png")
    }
    do {
        let data = try Data(contentsOf: url)
        return PNGImage.cgImage(from: data, name: "chrome/\(name).png")
    } catch {
        fatalError("chrome could not read \(url.path): \(error)")
    }
}

/// UIKit hold pad — survives a second finger on the canvas (SwiftUI DragGesture often cancels).
private struct HoldTouchPad: UIViewRepresentable {
    var onBegan: () -> Void
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> HoldTouchView {
        let view = HoldTouchView()
        view.coordinator = context.coordinator
        // Fully clear views are skipped by UIKit hit-testing; keep a tiny alpha.
        view.backgroundColor = UIColor(white: 1, alpha: 0.01)
        view.isMultipleTouchEnabled = false
        view.isUserInteractionEnabled = true
        // Zero-duration long press fires on touch-down without SwiftUI's gesture-arbitration delay.
        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePress)
        )
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delaysTouchesEnded = false
        press.delegate = context.coordinator
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ uiView: HoldTouchView, context: Context) {
        uiView.coordinator = context.coordinator
        context.coordinator.onBegan = onBegan
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan: () -> Void
        var onEnded: () -> Void
        private var holding = false

        init(onBegan: @escaping () -> Void, onEnded: @escaping () -> Void) {
            self.onBegan = onBegan
            self.onEnded = onEnded
        }

        @objc func handlePress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                began()
            case .ended, .cancelled, .failed:
                ended()
            default:
                break
            }
        }

        func began() {
            if holding { return }
            holding = true
            onBegan()
        }

        func ended() {
            guard holding else { return }
            holding = false
            onEnded()
        }

        // The canvas must keep receiving its own touches while New is held.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private final class HoldTouchView: UIView {
    var coordinator: HoldTouchPad.Coordinator?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.001, bounds.contains(point) else {
            return nil
        }
        return self
    }
}
