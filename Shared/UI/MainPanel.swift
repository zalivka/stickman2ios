import SwiftUI
import UIKit

struct MainPanel: View {
    static let width: CGFloat = 100
    static let pane = Color(red: 0x24 / 255, green: 0x25 / 255, blue: 0x30 / 255)
    static let play = Color(red: 1, green: 0x90 / 255, blue: 0)
    static let insert = Color(red: 0x72 / 255, green: 0xbd / 255, blue: 0)
    static let insertActive = Color(red: 0x85 / 255, green: 0xb8 / 255, blue: 0x39 / 255)
    static let editUnit = Color(red: 0, green: 0xbd / 255, blue: 0x78 / 255)
    static let editUnitActive = Color(red: 0, green: 0x9a / 255, blue: 0x62 / 255)
    static let editFrame = Color(red: 0x44 / 255, green: 0x9e / 255, blue: 0xc9 / 255)
    static let undo = Color(red: 0, green: 0x9a / 255, blue: 0xc4 / 255)
    static let tween = Color(red: 0, green: 0xc0 / 255, blue: 0xd8 / 255)
    static let reset = Color(red: 0xf3 / 255, green: 0x54 / 255, blue: 0x54 / 255)

    var onPlay: () -> Void = {}
    var playEnabled: Bool = true
    var onInsert: (() -> Void)? = nil
    var onEditUnit: (() -> Void)? = nil
    var onEditFrame: (() -> Void)? = nil
    var onUndo: (() -> Void)? = nil
    var undoEnabled: Bool = false
    var onMenu: (() -> Void)? = nil
    var onReset: (() -> Void)? = nil
    var onTween: (() -> Void)? = nil
    var tweenEnabled: Bool = true
    var insertActivated = false
    var editUnitActivated = false
    var editFrameActivated = false
    var menuActivated = false
    /// Tutorial play hint: every other control keeps its slot but is invisible and untappable.
    var onlyPlay = false

    @State private var undoFlashToken = 0
    @State private var undoFlashing = false

    var body: some View {
        VStack(spacing: 0) {
            if let onMenu {
                Button(action: onMenu) {
                    Image(decorative: Self.navIcon, scale: UIScreen.main.scale)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(menuActivated ? Color(white: 0.22) : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Menu")
                .opacity(onlyPlay ? 0 : 1)
                .allowsHitTesting(!onlyPlay)
            }
            chromeButton(
                icon: Self.playIcon,
                title: "PLAY",
                color: Self.play,
                activated: false,
                enabled: playEnabled,
                isPlay: true,
                action: onPlay
            )
            .tutorialHole(onlyPlay)
            if let onInsert {
                chromeButton(
                    icon: insertActivated ? Self.insertIconSel : Self.insertIcon,
                    title: "INSERT",
                    color: insertActivated ? .white : Self.insert,
                    activated: insertActivated,
                    action: onInsert
                )
            }
            if let onEditUnit {
                chromeButton(
                    icon: editUnitActivated ? Self.propsIconSel : Self.propsIcon,
                    title: "EDIT UNIT",
                    color: editUnitActivated ? .white : Self.editUnit,
                    activated: editUnitActivated,
                    activatedFill: Self.editUnitActive,
                    action: onEditUnit
                )
            }
            if let onEditFrame {
                chromeButton(
                    icon: editFrameActivated ? Self.frameIconSel : Self.frameIcon,
                    title: "EDIT FRAME",
                    color: editFrameActivated ? .white : Self.editFrame,
                    activated: editFrameActivated,
                    activatedFill: Self.editFrame,
                    action: onEditFrame
                )
                chromeButton(
                    icon: Self.undoIcon,
                    title: "UNDO",
                    color: undoFlashing ? .black : Self.undo,
                    activated: undoFlashing,
                    enabled: undoEnabled,
                    activatedFill: .white,
                    action: { tapUndo(onUndo ?? {}) }
                )
            }
            if let onTween {
                chromeButton(
                    icon: Self.tweenIcon,
                    title: "TWEEN",
                    color: Self.tween,
                    activated: false,
                    enabled: tweenEnabled,
                    action: onTween
                )
            }
            if let onReset {
                chromeButton(
                    icon: Self.resetIcon,
                    title: "RESET",
                    color: Self.reset,
                    activated: false,
                    action: onReset
                )
            }
            if onEditFrame == nil, let onUndo {
                chromeButton(
                    icon: Self.undoIcon,
                    title: "UNDO",
                    color: undoFlashing ? .black : Self.undo,
                    activated: undoFlashing,
                    enabled: undoEnabled,
                    activatedFill: .white,
                    action: { tapUndo(onUndo) }
                )
            }
            Spacer(minLength: 0)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Self.pane)
        .accessibilityIdentifier("main panel")
    }

    private func tapUndo(_ action: @escaping () -> Void) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        undoFlashToken += 1
        let token = undoFlashToken
        undoFlashing = true
        action()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            if token == undoFlashToken {
                undoFlashing = false
            }
        }
    }

    private func chromeButton(
        icon: CGImage,
        title: String,
        color: Color,
        activated: Bool,
        enabled: Bool = true,
        activatedFill: Color = insertActive,
        isPlay: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let hidden = onlyPlay && !isPlay
        return Button(action: action) {
            VStack(spacing: 4) {
                Image(decorative: icon, scale: UIScreen.main.scale)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(activated ? activatedFill : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || hidden)
        .opacity(hidden ? 0 : (enabled ? 1 : 0.4))
    }

    private static let navIcon = chromeImage("main_btn_nav")
    private static let playIcon = chromeImage("main_btn_play")
    private static let insertIcon = chromeImage("main_btn_insert")
    private static let insertIconSel = chromeImage("main_btn_insert_sel")
    private static let propsIcon = chromeImage("main_btn_props")
    private static let propsIconSel = chromeImage("main_btn_props_sel")
    private static let frameIcon = chromeImage("main_btn_frames")
    private static let frameIconSel = chromeImage("main_btn_frames_sel")
    private static let undoIcon = chromeImage("main_btn_undo")
    private static let tweenIcon = chromeImage("btn_tween")
    private static let resetIcon = chromeImage("btn_reset")

    private static func chromeImage(_ name: String) -> CGImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        else {
            fatalError("MainPanel missing chrome/\(name).png")
        }
        do {
            let data = try Data(contentsOf: url)
            return PNGImage.cgImage(from: data, name: "chrome/\(name).png")
        } catch {
            fatalError("MainPanel could not read \(url.path): \(error)")
        }
    }
}
