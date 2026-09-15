import SwiftUI

enum SideMenuAction: String {
    case save
    case export
    case createItems
    case editScene
    case audio
    case background
    case camera
    case speedEffects
    case debug
    case buy
    case settings
    case tutorials
}

struct SideMenu: View {
    static let width: CGFloat = 200

    var onPick: (SideMenuAction) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                row(.save, "Save project", "square.and.arrow.down")
                row(.export, "Export", "square.and.arrow.up")
                divider
                row(.createItems, "Create items", "plus.square")
                row(.editScene, "Edit scene", "slider.horizontal.3")
                row(.audio, "Add audio", "speaker.wave.2")
                row(.background, "Background", "photo")
                row(.camera, "Camera view", "camera")
                row(.speedEffects, "Speed effects", "speedometer")
                row(.debug, "Debug", "ladybug")
                divider
                row(.buy, "Unlock PRO *", "star")
                row(.settings, "App settings", "gearshape")
                row(.tutorials, "Tutorials", "questionmark.circle")
            }
            .padding(.bottom, 8)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(MainPanel.pane)
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
