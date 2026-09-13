import SwiftUI

struct FullscreenBackButton: View {
    var besideMainPanel: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: dismiss.callAsFunction) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .contentShape(Circle())
        }
        .accessibilityLabel("Back")
        .padding(.leading, besideMainPanel ? MainPanel.width + 8 : 8)
        .padding(.top, 8)
    }
}
