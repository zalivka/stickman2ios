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

    static func leadingWidth(panel: SkeletonToolsPanel) -> CGFloat {
        sidebarWidth + (panel == .none ? 0 : secondaryWidth)
    }
}

struct SkeletonLeftPanel: View {
    var panel: SkeletonToolsPanel
    var onMenu: () -> Void
    var onSelect: (SkeletonToolsPanel) -> Void
    var menuActivated: Bool

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

            VStack(spacing: 12) {
                toggle("BONES", accent: SkeletonChrome.bonesAccent, selected: panel == .bones) {
                    onSelect(panel == .bones ? .none : .bones)
                }
                toggle("DRAW", accent: SkeletonChrome.drawAccent, selected: panel == .draw) {
                    onSelect(panel == .draw ? .none : .draw)
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: SkeletonChrome.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(SkeletonChrome.pane)
    }

    private func toggle(_ title: String, accent: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? accent : SkeletonChrome.toggleIdle)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 0, topTrailingRadius: 0))
        }
        .buttonStyle(.plain)
    }

    private static let navIcon: CGImage = {
        guard let url = Bundle.main.url(forResource: "main_btn_nav", withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: "main_btn_nav", withExtension: "png")
        else {
            fatalError("SkeletonLeftPanel missing chrome/main_btn_nav.png")
        }
        do {
            let data = try Data(contentsOf: url)
            return PNGImage.cgImage(from: data, name: "chrome/main_btn_nav.png")
        } catch {
            fatalError("SkeletonLeftPanel could not read \(url.path): \(error)")
        }
    }()
}

struct SkeletonSecondaryPanel: View {
    var accent: Color

    var body: some View {
        HStack(spacing: 0) {
            accent.frame(width: SkeletonChrome.stripeWidth)
            SkeletonChrome.pane
        }
        .frame(width: SkeletonChrome.secondaryWidth)
        .frame(maxHeight: .infinity)
    }
}

struct SkeletonSideMenu: View {
    var onPick: () -> Void
    var onSaveAs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: SideMenu.topInset)
            row("Save as", action: onSaveAs)
            row("Preview", action: onPick)
            row("Audio", action: onPick)
            row("Settings", action: onPick)
            row("Help", action: onPick)
            Spacer(minLength: 0)
        }
        .frame(width: SideMenu.width)
        .frame(maxHeight: .infinity)
        .background(SkeletonChrome.pane)
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Color(white: 0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
