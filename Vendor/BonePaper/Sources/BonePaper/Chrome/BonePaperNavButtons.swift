import SwiftUI
import UIKit

struct BonePaperMenuButton: View {
    var activated: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(uiImage: BonePaperChrome.chromeImage("main_btn_nav"))
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .frame(width: BonePaperChrome.leftRail)
                .padding(.vertical, 6)
                .background(
                    activated ? Color(white: 0.22) : Color.clear,
                    ignoresSafeAreaEdges: []
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menu")
    }
}

private struct SkeletonSplitCloseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let ox = rect.minX + (rect.width - 24 * scale) / 2
        let oy = rect.minY + (rect.height - 24 * scale) / 2
        var path = Path()
        path.move(to: CGPoint(x: ox + 6 * scale, y: oy + 6 * scale))
        path.addLine(to: CGPoint(x: ox + 18 * scale, y: oy + 18 * scale))
        path.move(to: CGPoint(x: ox + 18 * scale, y: oy + 6 * scale))
        path.addLine(to: CGPoint(x: ox + 6 * scale, y: oy + 18 * scale))
        return path
    }
}

struct BonePaperPlacementCancelButton: View {
    private static let bgRed = Color(red: 0xE6 / 255, green: 0x38 / 255, blue: 0x36 / 255)
    var onCancel: () -> Void

    var body: some View {
        Button(action: onCancel) {
            SkeletonSplitCloseShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5 * (24.0 / 24.0), lineCap: .round))
                .frame(width: 24, height: 24)
                .frame(width: BonePaperChrome.leftRail, height: 61)
                .background(Self.bgRed)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel")
    }
}

struct BonePaperBackButton: View {
    var extraLeading: CGFloat = 0
    var onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: BonePaperChrome.tool, height: BonePaperChrome.tool)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .padding(.leading, BonePaperChrome.leftRail + extraLeading + 8)
        .padding(.top, 8)
    }
}

struct BonePaperUndoButton: View {
    var canUndo: Bool
    var showsCaption: Bool = true
    var onUndo: () -> Void

    var body: some View {
        Button(action: onUndo) {
            VStack(spacing: 1) {
                Image(uiImage: BonePaperChrome.chromeImage("skel_btn_undo"))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .frame(width: BonePaperChrome.tool, height: BonePaperChrome.tool)
                if showsCaption {
                    Text("undo")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white)
                }
            }
            .opacity(canUndo ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canUndo)
        .accessibilityLabel("Undo")
    }
}

struct BonePaperRedoButton: View {
    var canRedo: Bool
    var showsCaption: Bool = true
    var onRedo: () -> Void

    private static let purple = Color(red: 1, green: 0.35, blue: 0.72)

    var body: some View {
        Button(action: onRedo) {
            VStack(spacing: 1) {
                Image(uiImage: BonePaperChrome.chromeImage("skel_btn_undo").withRenderingMode(.alwaysTemplate))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Self.purple)
                    .scaleEffect(x: -1, y: 1)
                    .frame(width: BonePaperChrome.tool, height: BonePaperChrome.tool)
                if showsCaption {
                    Text("redo")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white)
                }
            }
            .opacity(canRedo ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canRedo)
        .accessibilityLabel("Redo")
    }
}

/// Android `drawable/check` — the fat Kurwa apply tick.
private struct KurwaCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 15.4142, y: 4.41421))
        path.addLine(to: CGPoint(x: 6, y: 13.8284))
        path.addLine(to: CGPoint(x: 0.585785, y: 8.41421))
        path.addLine(to: CGPoint(x: 3.41421, y: 5.58578))
        path.addLine(to: CGPoint(x: 6, y: 8.17157))
        path.addLine(to: CGPoint(x: 12.5858, y: 1.58578))
        path.closeSubpath()
        let scale = min(rect.width, rect.height) / 16
        let offset = CGSize(
            width: rect.minX + (rect.width - 16 * scale) / 2,
            height: rect.minY + (rect.height - 16 * scale) / 2
        )
        return path.applying(
            CGAffineTransform(translationX: offset.width, y: offset.height)
                .scaledBy(x: scale, y: scale)
        )
    }
}

struct BonePaperApply: View {
    var onApply: () -> Void

    var body: some View {
        Button(action: onApply) {
            KurwaCheck()
                .fill(Color.white)
                .frame(width: 36, height: 36)
                .frame(width: BonePaperChrome.rightRail, height: BonePaperChrome.rightRail)
                .background(BonePaperChrome.apply)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply")
    }
}
