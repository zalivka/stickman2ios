import SwiftUI

public struct BonePaperScreen: View {
    public static let worldSide = 1024

    @Environment(\.dismiss) private var dismiss
    @StateObject private var document: BonePaperDocument
    @State private var tool: BonePaperTool = .pen
    @State private var color: Color = .black
    @State private var brushSize: CGFloat = 14
    @State private var eraserSize: CGFloat = 14
    @State private var opacity: CGFloat = 1
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
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            ZStack {
                Color(white: 0.78).ignoresSafeArea()
                HStack(spacing: 0) {
                    BonePaperChrome.pane
                        .frame(width: BonePaperChrome.leftRail)
                        .frame(maxHeight: .infinity)
                    BonePaperCanvas(
                        document: document,
                        tool: tool,
                        color: UIColor(color),
                        brushSize: tool == .eraser ? eraserSize : brushSize,
                        opacity: opacity,
                        boneStart: boneStart,
                        boneTip: boneTip,
                        onion: onion,
                        zoom: $zoom,
                        fitInsets: BonePaperChrome.fitInsets(safe: safe)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    if showingStrokePreview {
                        BonePaperStrokePreview(
                            brushSize: tool == .eraser ? eraserSize : brushSize,
                            opacity: tool == .eraser ? 1 : opacity,
                            color: tool == .eraser ? Color.black.opacity(0.28) : color,
                            zoom: zoom,
                            label: tool == .eraser ? "Eraser" : "Brush",
                            showsOpacity: tool != .eraser
                        )
                        .padding(.top, safe.top + BonePaperChrome.pad)
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .top) {
                    BonePaperFillTestButton(selected: tool == .fill) {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            tool = .fill
                        }
                    }
                    .padding(.top, safe.top + BonePaperChrome.pad)
                }
                .overlay(alignment: .topLeading) {
                    BonePaperBackButton(onBack: { dismiss() })
                        .padding(.top, safe.top)
                }
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: BonePaperChrome.pad) {
                        BonePaperApply(onApply: apply)
                        BonePaperColorStrip(color: $color) {
                            tool = .pen
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.trailing, safe.trailing + BonePaperChrome.pad)
                    .padding(.top, safe.top + BonePaperChrome.pad)
                    .padding(.bottom, safe.bottom + BonePaperChrome.pad)
                }
                .overlay(alignment: .bottomLeading) {
                    BonePaperStrokeControls(
                        tool: $tool,
                        brushSize: $brushSize,
                        eraserSize: $eraserSize,
                        opacity: $opacity,
                        canUndo: document.canUndo,
                        onUndo: document.undo,
                        canRedo: document.canRedo,
                        onRedo: document.redo,
                        color: color,
                        onSeeking: { showingStrokePreview = $0 }
                    )
                    .padding(.bottom, safe.bottom)
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
