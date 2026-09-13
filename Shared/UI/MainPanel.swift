import SwiftUI

struct MainPanel: View {
    static let width: CGFloat = 80
    static let pane = Color(red: 0x24 / 255, green: 0x25 / 255, blue: 0x30 / 255)
    static let play = Color(red: 1, green: 0x90 / 255, blue: 0)

    var onPlay: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onPlay) {
                VStack(spacing: 4) {
                    Image(decorative: Self.playIcon, scale: UIScreen.main.scale)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                    Text("PLAY")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Self.play)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Self.pane)
        .accessibilityIdentifier("main panel")
    }

    private static let playIcon: CGImage = {
        guard let url = Bundle.main.url(forResource: "main_btn_play", withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: "main_btn_play", withExtension: "png")
        else {
            fatalError("MainPanel missing chrome/main_btn_play.png")
        }
        do {
            let data = try Data(contentsOf: url)
            guard let provider = CGDataProvider(data: data as CFData),
                  let image = CGImage(
                    pngDataProviderSource: provider,
                    decode: nil,
                    shouldInterpolate: true,
                    intent: .defaultIntent
                  )
            else {
                fatalError("MainPanel main_btn_play.png is not a PNG")
            }
            return image
        } catch {
            fatalError("MainPanel could not read \(url.path): \(error)")
        }
    }()
}
