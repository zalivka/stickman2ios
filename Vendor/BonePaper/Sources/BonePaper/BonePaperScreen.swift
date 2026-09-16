import SwiftUI

public struct BonePaperScreen: View {
    public static let worldSide = 1024

    @Environment(\.dismiss) private var dismiss
    @StateObject private var document: BonePaperDocument
    @State private var tool: BonePaperTool = .pen
    @State private var color: Color = .black
    @State private var brushSize: CGFloat = 14
    @State private var opacity: CGFloat = 1
    @State private var reveal: BonePaperReveal = .none
    @State private var zoom: CGFloat = 1
    @State private var showingStrokePreview = false

    private let boneStart: CGPoint?
    private let boneTip: CGPoint?
    private let onion: CGImage?
    private let onApply: ((BonePaperExport) -> Void)?

    public init() {
        self.init(source: nil, boneStart: nil, boneTip: nil, onion: nil, onApply: nil)
    }

    public init(
        source: CGImage?,
        boneStart: CGPoint?,
        boneTip: CGPoint?,
        onion: CGImage? = nil,
        onApply: ((BonePaperExport) -> Void)?
    ) {
        if let onion, onion.width != Self.worldSide || onion.height != Self.worldSide {
            fatalError("BonePaperScreen onion \(onion.width)x\(onion.height) != \(Self.worldSide)")
        }
        let width = source?.width ?? BonePaperDocument.defaultSide
        let height = source?.height ?? BonePaperDocument.defaultSide
        _document = StateObject(
            wrappedValue: BonePaperDocument(width: width, height: height, source: source)
        )
        self.boneStart = boneStart
        self.boneTip = boneTip
        self.onion = onion
        self.onApply = onApply
    }

    public var body: some View {
        ZStack {
            Color(white: 0.78).ignoresSafeArea()
            BonePaperCanvas(
                document: document,
                tool: tool,
                color: UIColor(color),
                brushSize: brushSize,
                opacity: opacity,
                boneStart: boneStart,
                boneTip: boneTip,
                onion: onion,
                zoom: $zoom
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                if showingStrokePreview {
                    BonePaperStrokePreview(
                        brushSize: brushSize,
                        opacity: opacity,
                        color: color,
                        zoom: zoom
                    )
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                BonePaperBackUndo(
                    canUndo: document.canUndo,
                    onBack: { dismiss() },
                    onUndo: document.undo
                )
            }
            .overlay(alignment: .topTrailing) {
                BonePaperApplyTools(
                    tool: $tool,
                    color: $color,
                    reveal: $reveal,
                    onApply: apply
                )
            }
            .overlay(alignment: .bottomLeading) {
                if tool != .pan {
                    BonePaperStrokeControls(
                        brushSize: $brushSize,
                        opacity: $opacity,
                        color: color,
                        onSeeking: { showingStrokePreview = $0 }
                    )
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private func apply() {
        onApply?(document.export())
        dismiss()
    }
}
