import SwiftUI

struct MainPanel: View {
    static let width: CGFloat = 80
    static let pane = Color(red: 0x24 / 255, green: 0x25 / 255, blue: 0x30 / 255)
    static let play = Color(red: 1, green: 0x90 / 255, blue: 0)
    static let insert = Color(red: 0x72 / 255, green: 0xbd / 255, blue: 0)
    static let insertActive = Color(red: 0x85 / 255, green: 0xb8 / 255, blue: 0x39 / 255)

    var onPlay: () -> Void = {}
    var playEnabled: Bool = true
    var onInsert: (() -> Void)? = nil
    var onMenu: (() -> Void)? = nil
    var onReset: (() -> Void)? = nil
    var insertActivated = false
    var menuActivated = false

    var body: some View {
        VStack(spacing: 0) {
            if let onMenu {
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
            }
            chromeButton(
                icon: Self.playIcon,
                title: "PLAY",
                color: Self.play,
                activated: false,
                enabled: playEnabled,
                action: onPlay
            )
            if let onInsert {
                chromeButton(
                    icon: insertActivated ? Self.insertIconSel : Self.insertIcon,
                    title: "INSERT",
                    color: insertActivated ? .white : Self.insert,
                    activated: insertActivated,
                    action: onInsert
                )
            }
            if let onReset {
                systemButton(
                    systemName: "arrow.counterclockwise",
                    title: "RESET",
                    color: .white,
                    action: onReset
                )
            }
            Spacer(minLength: 0)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Self.pane)
        .accessibilityIdentifier("main panel")
    }

    private func chromeButton(
        icon: CGImage,
        title: String,
        color: Color,
        activated: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
            .padding(.vertical, 8)
            .background(activated ? Self.insertActive : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func systemButton(
        systemName: String,
        title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let navIcon = chromeImage("main_btn_nav")
    private static let playIcon = chromeImage("main_btn_play")
    private static let insertIcon = chromeImage("main_btn_insert")
    private static let insertIconSel = chromeImage("main_btn_insert_sel")

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
