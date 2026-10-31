import SwiftUI

public struct BonePaperScreen: View {
    public static var worldSide: Int { BonePaperDocument.maxSide }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var document: BonePaperDocument
    @State private var tool: BonePaperTool = UIColor(BonePaperToolStore.color).cgColor.alpha == 0 ? .bucket : .pen
    @State private var fillMode: BonePaperTool = .bucket
    @State private var color: Color = BonePaperToolStore.color
    @State private var activeSwatchBaseColor: Color = BonePaperToolStore.color
    @State private var brushSize: CGFloat = BonePaperToolStore.brushSize
    @State private var eraserSize: CGFloat = BonePaperToolStore.eraserSize
    @State private var opacity: CGFloat = BonePaperToolStore.opacity
    @State private var drawingConfig: BonePaperDrawingConfig
    @State private var zoom: CGFloat = 1
    @State private var showingStrokePreview = false
    @State private var previewHideWorkItem: DispatchWorkItem?
    @State private var activeStrokeSetting: BonePaperStrokeSetting?
    @State private var activeSwatchTrack: BonePaperActiveSwatchTrack?
    @State private var stage = BonePaperStage()
    @State private var hoverColor: Color?
    @State private var chromeOpacity: Double
    @State private var leaving = false
    @State private var showFillWait = false

    private let boneStart: CGPoint?
    private let boneTip: CGPoint?
    private let onion: CGImage?
    private let paper: UIColor?
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
        /// Full-resolution paint buffer for `source`, `sample` times its size. Copied in without
        /// scaling so reopening loses no quality. A size mismatch falls back to the upscaled source.
        buffer: CGImage? = nil,
        initialDrawingConfig: BonePaperDrawingConfig? = nil,
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
        if let source, let buffer,
           buffer.width == source.width * BonePaperDocument.sample,
           buffer.height == source.height * BonePaperDocument.sample {
            _document = StateObject(
                wrappedValue: BonePaperDocument(width: width, height: height, source: source, buffer: buffer)
            )
        } else {
            _document = StateObject(
                wrappedValue: BonePaperDocument(width: width, height: height, source: source)
            )
        }
        _drawingConfig = State(initialValue: (initialDrawingConfig ?? BonePaperToolStore.fallbackConfig).sanitized())
        _chromeOpacity = State(initialValue: placement == nil ? 1 : 0)
        self.boneStart = boneStart
        self.boneTip = boneTip
        self.onion = onion
        self.paper = nil
        self.placement = placement
        self.onApply = onApply
        self.onClose = onClose
    }

    /// Blank fixed page over `sheet.paper`. The export is transparent where nothing was drawn.
    public init(sheet: BonePaperSheet, onApply: @escaping (BonePaperExport) -> Void) {
        _document = StateObject(wrappedValue: BonePaperDocument(sheet: sheet))
        _drawingConfig = State(initialValue: BonePaperToolStore.fallbackConfig)
        _chromeOpacity = State(initialValue: 1)
        boneStart = nil
        boneTip = nil
        onion = nil
        paper = sheet.paper
        placement = nil
        self.onApply = onApply
        onClose = nil
    }

    /// Blank page for drawing only. Apply stays visible and does nothing.
    public init(sheet: BonePaperSheet) {
        _document = StateObject(wrappedValue: BonePaperDocument(sheet: sheet))
        _drawingConfig = State(initialValue: BonePaperToolStore.fallbackConfig)
        _chromeOpacity = State(initialValue: 1)
        boneStart = nil
        boneTip = nil
        onion = nil
        paper = sheet.paper
        placement = nil
        onApply = nil
        onClose = nil
    }

    /// Same sheet as a blank page, with `buffer` already in the paint buffer.
    public init(sheet: BonePaperSheet, buffer: CGImage, onApply: @escaping (BonePaperExport) -> Void) {
        _document = StateObject(wrappedValue: BonePaperDocument(sheet: sheet, buffer: buffer))
        _drawingConfig = State(initialValue: BonePaperToolStore.fallbackConfig)
        _chromeOpacity = State(initialValue: 1)
        boneStart = nil
        boneTip = nil
        onion = nil
        paper = sheet.paper
        placement = nil
        self.onApply = onApply
        onClose = nil
    }

    public var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let topClearance: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 0 : safe.top
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
                        paper: paper,
                        placement: placement,
                        stage: stage,
                        zoom: $zoom,
                        fitInsets: BonePaperChrome.fitInsets(safe: safe, topClearance: topClearance),
                        onCommitStroke: recordCommittedStroke
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
                        .padding(.top, topClearance + BonePaperChrome.pad)
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topLeading) {
                    BonePaperBackButton(onBack: { leave() })
                        .padding(.top, topClearance)
                        .offset(x: -safe.leading)
                        .opacity(chromeOpacity)
                }
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: BonePaperChrome.pad) {
                        ZStack {
                            BonePaperApply(onApply: apply)
                            if let hoverColor {
                                BonePaperPipettePreview(color: hoverColor)
                            }
                        }
                        BonePaperColorStrip(
                            color: $color,
                            activeSwatchBaseColor: $activeSwatchBaseColor,
                            hover: $hoverColor,
                            activeTrack: $activeSwatchTrack,
                            itemPalette: drawingConfig.palette,
                            drawingConfig: drawingConfig,
                            stage: stage,
                            onPick: { _ in
                                if tool != .bucket, tool != .brushfill {
                                    tool = .pen
                                }
                            },
                            onPickTransparent: {
                                fillMode = .bucket
                                tool = .bucket
                            },
                            onSeekingBrightness: { dragging in
                                if dragging {
                                    activeStrokeSetting = nil
                                    previewHideWorkItem?.cancel()
                                    showingStrokePreview = true
                                } else {
                                    flashStrokePreview()
                                }
                            },
                            onFlashPreview: {
                                flashStrokePreview()
                            }
                        )
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.trailing, BonePaperChrome.pad)
                    .padding(.top, topClearance + BonePaperChrome.pad)
                    .opacity(chromeOpacity)
                }
                .overlay(alignment: .bottomLeading) {
                    BonePaperStrokeControls(
                        tool: $tool,
                        fillMode: $fillMode,
                        brushSize: $brushSize,
                        eraserSize: $eraserSize,
                        opacity: $opacity,
                        activeSetting: $activeStrokeSetting,
                        brushMarks: drawingConfig.brushSizes,
                        opacityMarks: drawingConfig.opacities,
                        eraserMarks: drawingConfig.eraserSizes,
                        canUndo: document.canUndo,
                        onUndo: document.undo,
                        canRedo: document.canRedo,
                        onRedo: document.redo,
                        color: color,
                        onToggleFillMode: {
                            fillMode = fillMode == .bucket ? .brushfill : .bucket
                            if fillMode == .brushfill, UIColor(color).cgColor.alpha == 0 {
                                color = .black
                                activeSwatchBaseColor = .black
                            }
                            tool = fillMode
                        },
                        onSeeking: { dragging in
                            if dragging {
                                activeSwatchTrack = nil
                                previewHideWorkItem?.cancel()
                                showingStrokePreview = true
                            } else {
                                previewHideWorkItem?.cancel()
                                showingStrokePreview = false
                            }
                        },
                        onFlashPreview: {
                            flashStrokePreview()
                        }
                    )
                    .padding(.bottom, safe.bottom)
                    .offset(x: -safe.leading)
                    .opacity(chromeOpacity)
                }
                .overlay {
                    if showFillWait {
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
        .task(id: document.filling) {
            guard document.filling else {
                showFillWait = false
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, document.filling else { return }
            showFillWait = true
        }
        .onAppear {
            if placement != nil {
                withAnimation(.easeInOut(duration: BonePaperStageView.transitionDuration)) {
                    chromeOpacity = 1
                }
            }
        }
        .onChange(of: brushSize) { _, next in
            BonePaperToolStore.brushSize = next
        }
        .onChange(of: eraserSize) { _, next in
            BonePaperToolStore.eraserSize = next
        }
        .onChange(of: opacity) { _, next in
            BonePaperToolStore.opacity = next
        }
        .onChange(of: color) { _, next in
            BonePaperToolStore.color = next
            if UIColor(next).cgColor.alpha == 0 {
                fillMode = .bucket
                if tool == .brushfill {
                    tool = .bucket
                }
            }
        }
        .onChange(of: activeStrokeSetting) { _, next in
            if next != nil {
                activeSwatchTrack = nil
            }
        }
        .onChange(of: activeSwatchTrack) { _, next in
            if next != nil {
                activeStrokeSetting = nil
            }
        }
    }

    private func flashStrokePreview() {
        previewHideWorkItem?.cancel()
        showingStrokePreview = true
        let work = DispatchWorkItem {
            showingStrokePreview = false
        }
        previewHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func recordCommittedStroke() {
        let activeUIColor = UIColor(color)
        let baseUIColor = UIColor(activeSwatchBaseColor)
        let paletteUIColor: UIColor = {
            if activeUIColor.cgColor.alpha == 0 {
                return activeUIColor
            }
            if baseUIColor.cgColor.alpha > 0,
               BonePaperDrawingConfig.hueKey(for: baseUIColor) == BonePaperDrawingConfig.hueKey(for: activeUIColor) {
                return baseUIColor
            }
            return activeUIColor
        }()

        switch tool {
        case .pen:
            guard activeUIColor.cgColor.alpha > 0 else { return }
            let hex = BonePaperColorStore.hex(from: paletteUIColor)
            drawingConfig.recordPenOrFill(colorHex: hex, brushSize: brushSize, opacity: opacity)
            drawingConfig.recordColorBrightness(baseColor: paletteUIColor, activeColor: activeUIColor)
        case .bucket, .brushfill:
            let hex = activeUIColor.cgColor.alpha > 0 ? BonePaperColorStore.hex(from: paletteUIColor) : nil
            drawingConfig.recordPenOrFill(colorHex: hex, brushSize: nil, opacity: opacity)
            if activeUIColor.cgColor.alpha > 0 {
                drawingConfig.recordColorBrightness(baseColor: paletteUIColor, activeColor: activeUIColor)
            }
        case .eraser:
            drawingConfig.recordEraser(eraserSize: eraserSize)
        case .pan:
            break
        }
        BonePaperToolStore.fallbackConfig = drawingConfig
    }

    private func apply() {
        guard let onApply else {
            return
        }
        var export = paper == nil ? document.export() : document.exportBuffer()
        export.drawingConfig = drawingConfig
        #if DEBUG
        document.saveRecording(
            result: export.image,
            onion: onion,
            paper: paper,
            boneStart: boneStart,
            boneTip: boneTip
        )
        #endif
        onApply(export)
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
