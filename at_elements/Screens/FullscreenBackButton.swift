import SwiftUI

struct FullscreenBackButton: View {
    var besideMainPanel: Bool = true
    var extraLeading: CGFloat = 0
    var padded: Bool = true
    var action: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: { if let action { action() } else { dismiss() } }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .contentShape(Circle())
        }
        .accessibilityLabel("Back")
        .padding(.leading, padded ? (besideMainPanel ? MainPanel.width : 0) + extraLeading + 8 : 0)
        .padding(.top, padded ? 8 : 0)
    }
}
