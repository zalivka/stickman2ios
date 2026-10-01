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

/// Shown when the tutorial cartoon finishes. "Start editing" leaves playback; "Replay" starts it again.
struct TutorialFinishOverlay: View {
    var onStart: () -> Void
    var onReplay: () -> Void

    var body: some View {
        ZStack {
            Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255, opacity: 0x88 / 255)
            VStack(spacing: 20) {
                Button(action: onStart) {
                    Text("Start editing")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 280, minHeight: 56)
                        .background(Self.startBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                Button(action: onReplay) {
                    Text("Replay")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// `#1336E4`
    private static let startBlue = Color(red: 0x13 / 255, green: 0x36 / 255, blue: 0xE4 / 255)
}
