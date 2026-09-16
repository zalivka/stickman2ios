import SwiftUI

public struct BonePaperScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var document = BonePaperDocument()
    @State private var tool: BonePaperTool = .pen
    @State private var color: Color = .black
    @State private var penSize: CGFloat = 14
    @State private var eraserSize: CGFloat = 14
    @State private var reveal: BonePaperReveal = .none

    public init() {}

    public var body: some View {
        ZStack {
            Color(white: 0.11).ignoresSafeArea()
            BonePaperCanvas(
                document: document,
                tool: tool,
                color: UIColor(color),
                brushSize: tool == .eraser ? eraserSize : penSize
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                topActions
            }
            .overlay(alignment: .bottomLeading) {
                BonePaperDrawTools(
                    tool: $tool,
                    color: $color,
                    penSize: $penSize,
                    eraserSize: $eraserSize,
                    reveal: $reveal
                )
            }
            .overlay(alignment: .bottomTrailing) {
                BonePaperHistoryButtons(
                    canUndo: document.canUndo,
                    canRedo: document.canRedo,
                    onUndo: document.undo,
                    onRedo: document.redo
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private var topActions: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color(red: 0.20, green: 0.78, blue: 0.35))
                .clipShape(Capsule())
        }
        .padding(.leading, 8)
        .padding(.trailing, 20)
        .padding(.top, 8)
    }
}
