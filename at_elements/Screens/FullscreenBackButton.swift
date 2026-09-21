import SwiftUI

struct FullscreenBackButton: View {
    var besideMainPanel: Bool = true
    var extraLeading: CGFloat = 0
    var padded: Bool = true
    var action: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BackCircleButton(action: { if let action { action() } else { dismiss() } })
            .padding(.leading, padded ? (besideMainPanel ? MainPanel.width : 0) + extraLeading + 8 : 0)
            .padding(.top, padded ? 8 : 0)
    }
}
