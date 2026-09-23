import SwiftUI

public struct BonePaperScreen: View {
    public static var worldSide: Int { BonePaperDocument.maxSide }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var document: BonePaperDocument
    @State private var tool: BonePaperTool = .pen
    @State private var color: Color = .black
    @State private var brushSize: CGFloat = 14
    @State private var eraserSize: CGFloat = 14
    @State private var opacity: CGFloat = 1
    @State private var zoom: CGFloat = 1
    @State private var showingStrokePreview = false
    @State private var stage = BonePaperStage()
    @State private var chromeOpacity: Double
    @State private var leaving = false

    private let boneStart: CGPoint?
    private let boneTip: CGPoint?
    private let onion: CGImage?
    private let placement: BonePaperPlacement?
    private let onApply: ((BonePaperExport) -> Void)?
    private let onClose: (() -> Void)?

    public init() {
        self.init(source: nil, boneStart: nil, boneTip: nil, onion: nil, onApply: nil)
    }

    /// With `placement`, present without the cover animation and a clear presentation background:
    /// the screen zooms from the caller's bone and back on its own, then calls `onClose`,
    /// which must remove the cover without animation.
    public init(
        source: CGImage?,
        boneStart: CGPoint?,
        boneTip: CGPoint?,
        onion: CGImage? = nil,
        placement: BonePaperPlacement? = nil,
        onApply: ((BonePaperExport) -> Void)?,
        onClose: (() -> Void)? = nil
    ) {
        if placement != nil, onClose == nil {
            fatalError("BonePaperScreen placement without onClose")
        }
        if let onion, onion.width != Self.worldSide || onion.height != Self.worldSide {
            fatalError("BonePaperScreen onion \(onion.width)x\(onion.height) != \(Self.worldSide)")
        }
        if placement != nil, boneStart == nil || boneTip == nil {
            fatalError("BonePaperScreen placement without a bone")
        }
        let width = source?.width ?? BonePaperDocument.defaultSide
        let height = source?.height ?? BonePaperDocument.defaultSide
        _document = StateObject(
            wrappedValue: BonePaperDocument(width: width, height: height, source: source)
        )
        _chromeOpacity = State(initialValue: placement == nil ? 1 : 0)
        self.boneStart = boneStart
        self.boneTip = boneTip
        self.onion = onion
        self.placement = placement
        self.onApply = onApply
        self.onClose = onClose
    }

    public var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            ZStack {
                Color(white: 0.78).ignoresSafeArea()
                    .opacity(chromeOpacity)
                HStack(spacing: 0) {
                    BonePaperChrome.pane
                        .frame(width: BonePaperChrome.leftRail)
                        .frame(maxHeight: .infinity)
                        .opacity(chromeOpacity)
                    BonePaperCanvas(
                        document: document,
                        tool: tool,
                        color: UIColor(color),
                        brushSize: tool == .eraser ? eraserSize : brushSize,
                        opacity: opacity,
                        boneStart: boneStart,
                        boneTip: boneTip,
                        onion: onion,
                        placement: placement,
                        stage: stage,
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
                .overlay(alignment: .topLeading) {
                    BonePaperBackButton(onBack: { leave() })
                        .padding(.top, safe.top)
                        .opacity(chromeOpacity)
                }
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: BonePaperChrome.pad) {
                        BonePaperApply(onApply: apply)
                        BonePaperColorStrip(color: $color) {
                            if tool != .fill {
                                tool = .pen
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.trailing, safe.trailing + BonePaperChrome.pad)
                    .padding(.top, safe.top + BonePaperChrome.pad)
                    .padding(.bottom, safe.bottom + BonePaperChrome.pad)
                    .opacity(chromeOpacity)
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
                    .opacity(chromeOpacity)
                }
                .overlay {
                    if document.filling {
                        ZStack {
                            Color.black.opacity(0.35).ignoresSafeArea()
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(.white)
                                Text("Filling")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }
            .allowsHitTesting(!leaving)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if placement != nil {
                withAnimation(.easeInOut(duration: BonePaperStageView.transitionDuration)) {
                    chromeOpacity = 1
                }
            }
        }
    }

    private func apply() {
        onApply?(document.export())
        leave()
    }

    private func leave() {
        if leaving {
            return
        }
        guard placement != nil, let onClose else {
            dismiss()
            return
        }
        leaving = true
        withAnimation(.easeInOut(duration: BonePaperStageView.transitionDuration)) {
            chromeOpacity = 0
        }
        stage.zoomBack(duration: BonePaperStageView.transitionDuration, completion: onClose)
    }
}
