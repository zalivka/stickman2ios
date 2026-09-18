import SwiftUI

enum SideMenuAction: String {
    case save
    case export
    case createItems
    case editScene
    case background
    case camera
    case debug
    case settings
}

struct SideMenu: View {
    static let width: CGFloat = 200
    private static let accent = Color(white: 0.92)

    var onPick: (SideMenuAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Self.accent
                .frame(width: 2)
            ScrollView {
                VStack(spacing: 0) {
                    row(.save, "Save project", "square.and.arrow.down")
                    row(.export, "Export", "square.and.arrow.up")
                    divider
                    row(.createItems, "Create items", "plus.square")
                    row(.editScene, "Edit scene", "slider.horizontal.3")
                    row(.background, "Background", "photo")
                    row(.camera, "Camera view", "camera")
                    row(.debug, "Debug", "ladybug")
                    divider
                    row(.settings, "App settings", "gearshape")
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MainPanel.pane)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("side menu")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(white: 0.55))
            .frame(height: 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }

    private func row(_ action: SideMenuAction, _ title: String, _ systemName: String) -> some View {
        Button {
            onPick(action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 16))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 15))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(white: 0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
