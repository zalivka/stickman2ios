import SwiftUI
import UIKit

/// Plays a sheet-mode `session.json` back through a real document at the recorded pace, with a fingertip marker.
/// Strokes keep their own timing (sped up by `strokeSpeed`); idle gaps between ops are squeezed.
public struct BonePaperPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player: BonePaperPlayer
    @State private var migrationToastShown = false

    public init(session: Data) {
        _player = StateObject(wrappedValue: BonePaperPlayer(session: session))
    }

    public var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            ZStack {
                Color(white: 0.78).ignoresSafeArea()
                BonePaperPlayerPage(document: player.document, player: player)
                    .padding(.horizontal, BonePaperChrome.tool + BonePaperChrome.pad * 2)
                    .padding(.vertical, BonePaperChrome.pad)
            }
            .overlay(alignment: .topLeading) {
                BonePaperBackButton(onBack: { dismiss() })
                    .padding(.top, safe.top)
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: BonePaperChrome.pad) {
                    BonePaperPlayerButton(symbol: player.running ? "pause.fill" : "play.fill") {
                        player.toggle()
                    }
                    BonePaperPlayerButton(symbol: "arrow.counterclockwise") {
                        player.restart()
                    }
                }
                .padding(.trailing, safe.trailing + BonePaperChrome.pad)
                .padding(.bottom, safe.bottom + BonePaperChrome.pad)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            player.attach()
            if !migrationToastShown, let from = player.migratedFrom {
                migrationToastShown = true
                BonePaperHexToast.showMessage("Old recording from a \(from) world")
            }
        }
        .onDisappear { player.detach() }
    }
}

struct BonePaperPlayerButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: BonePaperChrome.tool, height: BonePaperChrome.tool)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct BonePaperPlayerPage: View {
    @ObservedObject var document: BonePaperDocument
    @ObservedObject var player: BonePaperPlayer

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / CGFloat(player.width), geo.size.height / CGFloat(player.height))
            let size = CGSize(width: CGFloat(player.width) * scale, height: CGFloat(player.height) * scale)
            let origin = CGPoint(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2)
            let view = { (world: CGPoint) in
                CGPoint(
                    x: origin.x + (world.x - CGFloat(player.originX)) * scale,
                    y: origin.y + (world.y - CGFloat(player.originY)) * scale
                )
            }
            ZStack(alignment: .topLeading) {
                Color(uiColor: player.paper)
                    .frame(width: size.width, height: size.height)
                    .offset(x: origin.x, y: origin.y)
                Image(decorative: document.preview, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .offset(x: origin.x, y: origin.y)
                if let ripple = player.ripple {
                    Circle()
                        .stroke(Color.white.opacity(0.8 * (1 - ripple.progress)), lineWidth: 3)
                        .frame(width: 16 + 70 * ripple.progress, height: 16 + 70 * ripple.progress)
                        .position(view(ripple.at))
                }
                if let finger = player.finger {
                    let side: CGFloat = finger.touching ? 20 : 24
                    Circle()
                        .fill(Color(white: 0.35).opacity(finger.touching ? 0.45 : 0.18))
                        .overlay(Circle().stroke(Color.white.opacity(finger.touching ? 0.9 : 0.5), lineWidth: 1.5))
                        .frame(width: side, height: side)
                        .opacity(finger.alpha)
                        .position(view(finger.at))
                        .animation(.easeOut(duration: 0.08), value: finger.touching)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
