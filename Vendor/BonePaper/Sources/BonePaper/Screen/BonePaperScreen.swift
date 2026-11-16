import SwiftUI
import UIKit

public struct BonePaperScreen: View {
    public static var worldSide: Int { BonePaperDocument.maxSide }
    /// Provider registered by the app target to build the image picker sheet (e.g. `AssetsLibrarySheet`).
    @MainActor public static var imagePickerSheetProvider: ((
        @escaping (CGImage) -> Void,
        @escaping () -> Void
    ) -> AnyView)?

    @Environment(\.dismiss) var dismiss
    @StateObject var document: BonePaperDocument
    @StateObject var framesSession: BonePaperFramesSession
    @State var tool: BonePaperTool = UIColor(BonePaperToolStore.color).cgColor.alpha == 0 ? .bucket : .pen
    @State var fillMode: BonePaperTool = .bucket
    @State var color: Color = BonePaperToolStore.color
    @State var activeSwatchBaseColor: Color = BonePaperToolStore.color
    @State var brushSize: CGFloat = BonePaperToolStore.brushSize
    @State var eraserSize: CGFloat = BonePaperToolStore.eraserSize
    @State var opacity: CGFloat = BonePaperToolStore.opacity
    @State var drawingConfig: BonePaperDrawingConfig
    @State var zoom: CGFloat = 1
    @State var showingStrokePreview = false
    @State var previewHideWorkItem: DispatchWorkItem?
    @State var activeStrokeSetting: BonePaperStrokeSetting?
    @State var activeSwatchTrack: BonePaperActiveSwatchTrack?
    @State var stage = BonePaperStage()
    @State var hoverColor: Color?
    @State var chromeOpacity: Double
    @State var leaving = false
    @State var showFillWait = false
    @State var showingMenu = false
    @State var showFramesPanel = false
    @State var isRearrangingFrames = false
    @State var hasImagePlacement = false
    @State var showingImagePicker = false
    @State var brushOffset: Double = Double(BonePaperToolStore.brushOffset)
    @State var errorStripeOpacity: Double = 0
    @State var errorStripeTask: Task<Void, Never>?

    let boneLength: CGFloat?
    let staticBoneStart: CGPoint?
    let staticBoneTip: CGPoint?
    let onion: CGImage?
    let paper: UIColor?
    let placement: BonePaperPlacement?
    let supportsFramesStrip: Bool
    let onApply: ((BonePaperExport) -> Void)?
    let onApplyFrames: (([BonePaperFrameExport], Int) -> Void)?
    let onClose: (() -> Void)?

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
        mask: CGImage? = nil,
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
        let config = (initialDrawingConfig ?? BonePaperToolStore.fallbackConfig).sanitized()
        let xOff = boneStart.map { -$0.x } ?? 0
        let yOff = boneStart.map { -$0.y } ?? 0
        let session = BonePaperFramesSession(
            inputs: [
                BonePaperFrameInput(
                    state: 0,
                    weight: 1,
                    source: source,
                    buffer: buffer,
                    mask: mask,
                    xOffset: xOff,
                    yOffset: yOff,
                    drawingConfig: config
                )
            ],
            initialState: 0,
            defaultWidth: width,
            defaultHeight: height,
            defaultXOffset: xOff,
            defaultYOffset: yOff
        )
        _framesSession = StateObject(wrappedValue: session)
        if let source, let buffer,
           buffer.width == source.width * BonePaperDocument.sample,
           buffer.height == source.height * BonePaperDocument.sample {
            _document = StateObject(
                wrappedValue: BonePaperDocument(width: width, height: height, source: source, buffer: buffer, mask: mask)
            )
        } else {
            let doc = BonePaperDocument(width: width, height: height, source: source)
            if let maskAlpha = session.activeSnapshot.maskAlpha {
                doc.loadFrameBuffer(
                    session.activeSnapshot.buffer,
                    maskAlpha: maskAlpha,
                    width: width,
                    height: height,
                    originX: session.activeSnapshot.originX,
                    originY: session.activeSnapshot.originY,
                    extraLeft: 0,
                    extraTop: 0
                )
            }
            _document = StateObject(wrappedValue: doc)
        }
        _drawingConfig = State(initialValue: config)
        _chromeOpacity = State(initialValue: placement == nil ? 1 : 0)
        if let boneStart, let boneTip {
            self.boneLength = hypot(boneTip.x - boneStart.x, boneTip.y - boneStart.y)
        } else {
            self.boneLength = nil
        }
        let hasBone = boneStart != nil && boneTip != nil
        self.staticBoneStart = boneStart
        self.staticBoneTip = boneTip
        self.onion = onion
        self.paper = nil
        self.placement = placement
        self.supportsFramesStrip = hasBone
        self.onApply = onApply
        self.onApplyFrames = nil
        self.onClose = onClose
    }

    /// Multi-frame bone editor initializer.
    public init(
        frames: [BonePaperFrameInput],
        initialState: Int = 0,
        boneLength: CGFloat,
        defaultWidth: Int = BonePaperDocument.defaultSide,
        defaultHeight: Int = BonePaperDocument.defaultSide,
        defaultXOffset: CGFloat = 0,
        defaultYOffset: CGFloat = 0,
        onion: CGImage? = nil,
        placement: BonePaperPlacement? = nil,
        onApplyFrames: @escaping ([BonePaperFrameExport], Int) -> Void,
        onClose: (() -> Void)? = nil
    ) {
        if placement != nil, onClose == nil {
            fatalError("BonePaperScreen placement without onClose")
        }
        if let onion, onion.width != Self.worldSide || onion.height != Self.worldSide {
            fatalError("BonePaperScreen onion \(onion.width)x\(onion.height) != \(Self.worldSide)")
        }
        let session = BonePaperFramesSession(
            inputs: frames,
            initialState: initialState,
            defaultWidth: defaultWidth,
            defaultHeight: defaultHeight,
            defaultXOffset: defaultXOffset,
            defaultYOffset: defaultYOffset
        )
        let active = session.activeSnapshot
        let doc = BonePaperDocument(width: active.width, height: active.height, source: nil)
        doc.loadFrameBuffer(
            active.buffer,
            maskAlpha: active.maskAlpha,
            width: active.width,
            height: active.height,
            originX: active.originX,
            originY: active.originY,
            extraLeft: active.extraLeft,
            extraTop: active.extraTop
        )
        _framesSession = StateObject(wrappedValue: session)
        _document = StateObject(wrappedValue: doc)
        _drawingConfig = State(initialValue: active.drawingConfig)
        _chromeOpacity = State(initialValue: placement == nil ? 1 : 0)
        self.boneLength = boneLength
        self.staticBoneStart = nil
        self.staticBoneTip = nil
        self.onion = onion
        self.paper = nil
        self.placement = placement
        self.supportsFramesStrip = true
        self.onApply = nil
        self.onApplyFrames = onApplyFrames
        self.onClose = onClose
    }

    /// Blank fixed page over `sheet.paper`. The export is transparent where nothing was drawn.
    public init(sheet: BonePaperSheet, onApply: @escaping (BonePaperExport) -> Void) {
        _document = StateObject(wrappedValue: BonePaperDocument(sheet: sheet))
        _framesSession = StateObject(
            wrappedValue: BonePaperFramesSession(
                inputs: [],
                defaultWidth: sheet.width,
                defaultHeight: sheet.height
            )
        )
        _drawingConfig = State(initialValue: BonePaperToolStore.fallbackConfig)
        _chromeOpacity = State(initialValue: 1)
        boneLength = nil
        staticBoneStart = nil
        staticBoneTip = nil
        onion = nil
        paper = sheet.paper
        placement = nil
        supportsFramesStrip = false
        self.onApply = onApply
        onApplyFrames = nil
        onClose = nil
    }

    /// Blank page for drawing only. Apply stays visible and does nothing.
    public init(sheet: BonePaperSheet) {
        _document = StateObject(wrappedValue: BonePaperDocument(sheet: sheet))
        _framesSession = StateObject(
            wrappedValue: BonePaperFramesSession(
                inputs: [],
                defaultWidth: sheet.width,
                defaultHeight: sheet.height
            )
        )
        _drawingConfig = State(initialValue: BonePaperToolStore.fallbackConfig)
        _chromeOpacity = State(initialValue: 1)
        boneLength = nil
        staticBoneStart = nil
        staticBoneTip = nil
        onion = nil
        paper = sheet.paper
        placement = nil
        supportsFramesStrip = false
        onApply = nil
        onApplyFrames = nil
        onClose = nil
    }

    /// Same sheet as a blank page, with `buffer` already in the paint buffer.
    public init(sheet: BonePaperSheet, buffer: CGImage, onApply: @escaping (BonePaperExport) -> Void) {
        _document = StateObject(wrappedValue: BonePaperDocument(sheet: sheet, buffer: buffer))
        _framesSession = StateObject(
            wrappedValue: BonePaperFramesSession(
                inputs: [],
                defaultWidth: sheet.width,
                defaultHeight: sheet.height
            )
        )
        _drawingConfig = State(initialValue: BonePaperToolStore.fallbackConfig)
        _chromeOpacity = State(initialValue: 1)
        boneLength = nil
        staticBoneStart = nil
        staticBoneTip = nil
        onion = nil
        paper = sheet.paper
        placement = nil
        supportsFramesStrip = false
        self.onApply = onApply
        onApplyFrames = nil
        onClose = nil
    }

    var activeBoneStart: CGPoint? {
        if let staticBoneStart {
            return staticBoneStart
        }
        guard boneLength != nil else { return nil }
        let active = framesSession.activeSnapshot
        return CGPoint(x: -active.baseXOffset, y: -active.baseYOffset)
    }

    var activeBoneTip: CGPoint? {
        if let staticBoneTip {
            return staticBoneTip
        }
        guard let boneLength else { return nil }
        let active = framesSession.activeSnapshot
        return CGPoint(x: boneLength - active.baseXOffset, y: -active.baseYOffset)
    }

    var activeOnion: CGImage? {
        if framesSession.selectedState > 0 {
            return framesSession.previousFrameOnion
        }
        return onion
    }
}
