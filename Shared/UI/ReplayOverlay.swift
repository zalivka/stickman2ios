import SwiftUI

struct ReplayOverlay: View {
    var text: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255, opacity: 0x88 / 255))
    }
}
