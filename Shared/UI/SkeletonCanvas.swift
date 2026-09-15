import SwiftUI
import UIKit

struct SkeletonLayout {
    var minX: CGFloat
    var minY: CGFloat
    var scale: CGFloat
    var originX: CGFloat
    var originY: CGFloat

    static func fit(sceneWidth: CGFloat, sceneHeight: CGFloat, in size: CGSize) -> SkeletonLayout {
        if sceneWidth <= 0 || sceneHeight <= 0 {
            fatalError("SkeletonLayout scene size \(sceneWidth)x\(sceneHeight)")
        }
        let pad: CGFloat = 24
        let availW = max(size.width - pad * 2, 1)
        let availH = max(size.height - pad * 2, 1)
        let scale = min(availW / sceneWidth, availH / sceneHeight)
        if scale <= 0 {
            fatalError("SkeletonLayout scale is \(scale)")
        }
        return SkeletonLayout(
            minX: 0,
            minY: 0,
            scale: scale,
            originX: (size.width - sceneWidth * scale) / 2,
            originY: (size.height - sceneHeight * scale) / 2
        )
    }

    func screenPoint(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(
            x: originX + (x - minX) * scale,
            y: originY + (y - minY) * scale
        )
    }

    func graphPoint(screen: CGPoint) -> CGPoint {
        CGPoint(
            x: minX + (screen.x - originX) / scale,
            y: minY + (screen.y - originY) / scale
        )
    }

    func pinched(around focus: CGPoint, factor: CGFloat, minScale: CGFloat, maxScale: CGFloat) -> SkeletonLayout {
        if factor <= 0 {
            fatalError("SkeletonLayout pinch factor is \(factor)")
        }
        let graph = graphPoint(screen: focus)
        let next = min(max(scale * factor, minScale), maxScale)
        var copy = self
        copy.scale = next
        copy.originX = focus.x - (graph.x - minX) * next
        copy.originY = focus.y - (graph.y - minY) * next
        return copy
    }

    func panned(dx: CGFloat, dy: CGFloat) -> SkeletonLayout {
        var copy = self
        copy.originX += dx
        copy.originY += dy
        return copy
    }

    static let sceneSpace = SkeletonLayout(minX: 0, minY: 0, scale: 1, originX: 0, originY: 0)
}

private enum ItemHandlerKind {
    case move, rotate, scale
}

private enum HandlerArtwork {
    static let move = image("mover")
    static let rotate = image("rotator")
    static let scale = image("scaler")

    static func image(_ name: String) -> CGImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "handlers")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        else {
            fatalError("SkeletonCanvas missing handlers/\(name).png")
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
                fatalError("SkeletonCanvas '\(name).png' is not a PNG")
            }
            return image
        } catch {
            fatalError("SkeletonCanvas could not read \(url.path): \(error)")
        }
    }
}

enum SkeletonCanvasMode {
    case editor
    case preview
    case camera
    case background
    case skeleton
}

struct SkeletonCanvas: View {
    static let color = Color(red: 1, green: 0x71 / 255, blue: 0)
    static let edgeWidth: CGFloat = 1
    static let nodeRadius: CGFloat = 3
    static let baseNodeRadius: CGFloat = 4.4
    static let hitRadius: CGFloat = 28
    static let handlerHitRadius: CGFloat = 32
    static let pane = Color(red: 0x3d / 255, green: 0x3e / 255, blue: 0x4c / 255)
    static let checkerLight = Color(red: 0xf2 / 255, green: 0xf2 / 255, blue: 0xf2 / 255)
    static let checkerSquare: CGFloat = 12
    static let boneCommon = Color(red: 0, green: 0xb2 / 255, blue: 1)
    static let boneSlave = Color(red: 1, green: 0x26 / 255, blue: 0)
    static let boneMaster = Color(red: 0x88 / 255, green: 0xe2 / 255, blue: 0x0d / 255)
    static let boneNodeRadius: CGFloat = 4
    static let boneEdgeWidth: CGFloat = 3
    static let boneBaseRingRadius: CGFloat = 8.5
    static let boneBaseRingWidth: CGFloat = 2
    /// Android EditView.COLOR_NODE_ACTIVE — bone-create preview.
    static let boneCreatePreview = Color(red: 1, green: 0xaf / 255, blue: 0x3b / 255)
    /// Android CAPTURE_RAD in scene units, used as a screen-space multiplier with layout.scale.
    static let boneCreateCapture: CGFloat = 60
    /// Android BONE_CREATE_MIN_DRAG (= NODE_RADIUS * 2) in unscaled item units.
    static let boneCreateMinDrag: CGFloat = 16
    /// Android COLOR_SELECTION_HIGHLIGHT
    static let boneSelected = Color(red: 0, green: 1, blue: 0)
    /// Android vacant-point flash (`#51be00` @ 196/255).
    static let vacantExpose = Color(red: 0x51 / 255, green: 0xbe / 255, blue: 0).opacity(196 / 255)
    /// Android `EditView.EXPOSE_RADIUS` in scene units.
    static let vacantExposeRadius: CGFloat = 30
    static let sceneBound = Color(red: 0, green: 0xd7 / 255, blue: 1)
    static let sceneFill = pane
    static let previewBackdrop = Color(red: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255)
    static let cameraFrame = Color(red: 1, green: 0x2d / 255, blue: 0x6f / 255)

    @Binding var unit: StickmanUnit
    var frameUnits: [StickmanUnit] = []
    var assets: UnitAssets?
    var backgrounds: BackgroundAssets?
    var bgName: String?
    var bgMove: PictureMove = .identity
    var cameraMove: PictureMove = .identity
    var sceneWidth: CGFloat
    var sceneHeight: CGFloat
    var currentIndex: Int = 0
    var sceneFill: Color = Self.sceneFill
    var mode: SkeletonCanvasMode = .editor
    var showSkeleton: Bool = true
    /// Live hold/selection flags — reference type so touch closures never see a stale copy.
    var editSession: SkeletonEditSession?
    var selectedPointId: Binding<Int?> = .constant(nil)
    /// Scene-editor selection. `nil` means no unit is active.
    var selectedUnitName: Binding<String?> = .constant(nil)
    /// Bumped when asset draw-order changes so the canvas redraws.
    var layerEpoch: Int = 0
    /// Android `toggleVacantPoints` — green circles over all nodes.
    var exposeVacantPoints: Bool = false
    var onCameraChange: ((PictureMove) -> Void)? = nil
    @State private var layout: SkeletonLayout?
    @State private var layoutSize: CGSize = .zero
    @State private var fitScale: CGFloat = 1
    @State private var handlerMove = CGPoint.zero
    @State private var handlerRotate = CGPoint.zero
    @State private var handlerScale = CGPoint.zero
    @State private var touchScreen: CGPoint?
    @State private var dragRef = DragRef()
    @State private var boneCreateStartId: Int?
    @State private var boneCreateEnd: CGPoint?

    private final class DragRef {
        var nodeId: Int?
        var handler: ItemHandlerKind?
        var lastScreen: CGPoint?
        var handlerX: CGFloat = 0
        var handlerY: CGFloat = 0
        var rotateDiff: CGFloat = 0
        var scalePivotDist: CGFloat = 0
        var scaleStart: CGFloat = 1
        var touchOffsetX: CGFloat = 0
        var touchOffsetY: CGFloat = 0
        var panning = false
    }

    var body: some View {
        GeometryReader { proxy in
            let _ = layerEpoch
            Canvas { context, size in
                let layout = resolvedLayout(size: size)
                switch mode {
                case .editor, .camera, .background:
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.pane))
                case .skeleton:
                    drawCheckerboard(context: &context, size: size, layout: layout)
                case .preview:
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.previewBackdrop))
                }
                switch mode {
                case .editor:
                    drawScene(context: &context, layout: layout)
                    drawSceneBound(context: &context, layout: layout)
                    for drawn in unitsToDraw {
                        drawUnit(drawn, context: &context, layout: layout)
                    }
                    drawCameraRectangle(context: &context, layout: layout)
                    drawHandlers(context: &context, layout: layout)
                    drawTouchPoint(context: &context)
                case .skeleton:
                    for drawn in unitsToDraw {
                        drawUnit(drawn, context: &context, layout: layout)
                    }
                    drawBoneCreatePreview(context: &context, layout: layout)
                    if exposeVacantPoints {
                        drawVacantPoints(unit, context: &context, layout: layout)
                    }
                    drawTouchPoint(context: &context)
                case .preview:
                    drawAppliedCamera(context: &context, layout: layout, clip: true)
                case .camera:
                    drawAppliedCamera(context: &context, layout: layout, clip: false)
                    drawCameraWindow(context: &context, layout: layout)
                case .background:
                    drawScene(context: &context, layout: layout)
                    drawSceneBound(context: &context, layout: layout)
                    for drawn in unitsToDraw {
                        drawUnit(drawn, context: &context, layout: layout)
                    }
                }
            }
            .overlay {
                if mode == .editor || mode == .skeleton {
                    SkeletonTouchOverlay(
                        useRawTouches: mode == .skeleton,
                        onBegan: { handleDrag(at: $0, size: proxy.size, began: true) },
                        onChanged: { handleDrag(at: $0, size: proxy.size, began: false) },
                        onEnded: { _ in endTouch() },
                        onDoubleTap: { handleEmptyDoubleTap(at: $0, size: proxy.size) },
                        onPinchBegan: { endTouch() },
                        onPinch: { handlePinch(focus: $0, factor: $1) }
                    )
                } else if mode == .camera {
                    CameraTouchOverlay(
                        currentIndex: currentIndex,
                        cameraMove: cameraMove,
                        layoutScale: resolvedLayout(size: proxy.size).scale,
                        windowCenter: CGPoint(x: sceneWidth / 2, y: sceneHeight / 2),
                        onChange: cameraChangeHandler
                    )
                }
            }
            .onAppear { freezeLayout(in: proxy.size) }
            .onChange(of: proxy.size) { _, newSize in
                freezeLayout(in: newSize)
            }
            .onChange(of: currentIndex) { _, _ in
                endTouch()
            }
            .onChange(of: boneCreateHoldFlag) { _, on in
                if !on {
                    resetBoneCreateGesture()
                }
            }
        }
    }

    private var boneCreateHoldFlag: Bool {
        editSession?.boneCreateHoldMode ?? false
    }

    private var cameraChangeHandler: (PictureMove) -> Void {
        guard let onCameraChange else {
            fatalError("SkeletonCanvas camera mode missing onCameraChange")
        }
        return onCameraChange
    }

    private var unitsToDraw: [StickmanUnit] {
        let source = frameUnits.isEmpty ? [unit] : frameUnits
        return source.sorted {
            if $0.arrange != $1.arrange {
                return $0.arrange < $1.arrange
            }
            return $0.name < $1.name
        }
    }

    private func drawUnit(_ drawn: StickmanUnit, context: inout GraphicsContext, layout: SkeletonLayout) {
        if drawn.unitType == .bubble {
            if drawn.alpha < 1 {
                context.drawLayer { layer in
                    layer.opacity = Double(drawn.alpha)
                    layer.drawLayer { opaque in
                        drawBubbleText(drawn, context: &opaque, layout: layout)
                    }
                }
            } else {
                drawBubbleText(drawn, context: &context, layout: layout)
            }
        } else if let assets {
            if drawn.alpha < 1 {
                context.drawLayer { layer in
                    layer.opacity = Double(drawn.alpha)
                    layer.drawLayer { opaque in
                        drawBitmaps(drawn, context: &opaque, layout: layout, assets: assets)
                    }
                }
            } else {
                drawBitmaps(drawn, context: &context, layout: layout, assets: assets)
            }
        }
        if showSkeleton {
            drawSkeleton(drawn, context: &context, layout: layout)
            if FeatureFlags.debugDrawTouchCapture {
                drawTouchCapture(drawn, context: &context, layout: layout)
            }
        }
    }

    private func drawBubbleText(_ drawn: StickmanUnit, context: inout GraphicsContext, layout: SkeletonLayout) {
        guard let bubble = drawn.bubble else {
            fatalError("SkeletonCanvas unit '\(drawn.name)' type=bubble missing meta")
        }
        let start = drawn.point(id: 1)
        let end = drawn.point(id: 2)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let rgba = bubble.rgba
        let text = Text(bubble.text)
            .font(.system(size: bubble.fontSize))
            .foregroundColor(Color(red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a))
        context.drawLayer { ctx in
            ctx.translateBy(
                x: layout.originX - layout.minX * layout.scale,
                y: layout.originY - layout.minY * layout.scale
            )
            ctx.scaleBy(x: layout.scale, y: layout.scale)
            ctx.translateBy(x: start.x, y: start.y)
            ctx.rotate(by: Angle(radians: angle))
            ctx.scaleBy(x: drawn.scale, y: drawn.scale)
            let resolved = ctx.resolve(text)
            if bubble.oneLiner {
                ctx.draw(resolved, at: .zero, anchor: .topLeading)
            } else {
                ctx.draw(resolved, in: CGRect(x: 0, y: 0, width: 150, height: 2000))
            }
        }
    }

    private func drawCheckerboard(context: inout GraphicsContext, size: CGSize, layout: SkeletonLayout) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.checkerLight))
        let square = Self.checkerSquare * layout.scale
        if square < 6 {
            return
        }
        let origin = layout.screenPoint(x: 0, y: 0)
        let firstCol = Int(floor(-origin.x / square))
        let lastCol = Int(ceil((size.width - origin.x) / square))
        let firstRow = Int(floor(-origin.y / square))
        let lastRow = Int(ceil((size.height - origin.y) / square))
        var path = Path()
        for row in firstRow..<lastRow {
            for col in firstCol..<lastCol where (row + col) % 2 != 0 {
                path.addRect(CGRect(
                    x: origin.x + CGFloat(col) * square,
                    y: origin.y + CGFloat(row) * square,
                    width: square,
                    height: square
                ))
            }
        }
        context.fill(path, with: .color(.white))
    }

    private func drawSkeleton(_ drawn: StickmanUnit, context: inout GraphicsContext, layout: SkeletonLayout) {
        let bones = mode == .skeleton
        let selectedId = selectedPointId.wrappedValue
        let selectedEdge = selectedId.flatMap { drawn.upperEdge(of: $0) }
        for edge in drawn.edges {
            let from = drawn.point(id: edge.from)
            let to = drawn.point(id: edge.to)
            var path = Path()
            path.move(to: layout.screenPoint(x: from.x, y: from.y))
            path.addLine(to: layout.screenPoint(x: to.x, y: to.y))
            let isSelected = bones && selectedEdge?.from == edge.from && selectedEdge?.to == edge.to
            let edgeColor: Color
            if isSelected {
                edgeColor = Self.boneSelected
            } else if bones {
                edgeColor = Self.boneCommon
            } else {
                edgeColor = Self.color
            }
            context.stroke(
                path,
                with: .color(edgeColor),
                style: StrokeStyle(lineWidth: bones ? Self.boneEdgeWidth : Self.edgeWidth, lineCap: .butt)
            )
        }
        for point in drawn.points {
            let center = layout.screenPoint(x: point.x, y: point.y)
            let isSelected = bones && point.id == selectedId
            let color: Color
            if isSelected {
                color = Self.boneSelected
            } else if bones {
                color = Self.boneColor(point)
            } else {
                color = Self.color
            }
            let radius: CGFloat
            if bones {
                radius = isSelected ? Self.boneNodeRadius * 1.5 : Self.boneNodeRadius
            } else {
                radius = point.isBase ? Self.baseNodeRadius : Self.nodeRadius
            }
            context.fill(Path(ellipseIn: Self.square(around: center, radius: radius)), with: .color(color))
            if bones, point.isBase {
                context.stroke(
                    Path(ellipseIn: Self.square(around: center, radius: Self.boneBaseRingRadius)),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: Self.boneBaseRingWidth)
                )
            }
        }
    }

    private static func boneColor(_ point: StickmanPoint) -> Color {
        switch point.attachable {
        case .none: boneCommon
        case .slave: boneSlave
        case .master: boneMaster
        }
    }

    private static func square(around center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    private func drawBoneCreatePreview(context: inout GraphicsContext, layout: SkeletonLayout) {
        guard boneCreateHoldFlag, let startId = boneCreateStartId, let end = boneCreateEnd else {
            return
        }
        let start = unit.point(id: startId)
        let from = layout.screenPoint(x: start.x, y: start.y)
        let to = layout.screenPoint(x: end.x, y: end.y)
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        let color = Self.boneCreatePreview.opacity(220 / 255)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        let tipRadius = Self.boneNodeRadius * 1.5
        context.fill(Path(ellipseIn: Self.square(around: to, radius: tipRadius)), with: .color(color))
    }

    private func drawVacantPoints(_ drawn: StickmanUnit, context: inout GraphicsContext, layout: SkeletonLayout) {
        let radius = Self.vacantExposeRadius * layout.scale
        for point in drawn.points {
            let center = layout.screenPoint(x: point.x, y: point.y)
            context.fill(
                Path(ellipseIn: Self.square(around: center, radius: radius)),
                with: .color(Self.vacantExpose)
            )
        }
    }

    private func drawTouchCapture(_ drawn: StickmanUnit, context: inout GraphicsContext, layout: SkeletonLayout) {
        let radius = Self.hitRadius
        let color = Color.cyan.opacity(180 / 255)
        for point in drawn.points {
            let center = layout.screenPoint(x: point.x, y: point.y)
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(color),
                style: StrokeStyle(lineWidth: 2)
            )
        }
    }

    private func drawTouchPoint(context: inout GraphicsContext) {
        guard let touch = touchScreen else { return }
        let radius: CGFloat = 5
        context.fill(
            Path(ellipseIn: CGRect(
                x: touch.x - radius,
                y: touch.y - radius,
                width: radius * 2,
                height: radius * 2
            )),
            with: .color(.red)
        )
        var cross = Path()
        cross.move(to: CGPoint(x: touch.x - 10, y: touch.y))
        cross.addLine(to: CGPoint(x: touch.x + 10, y: touch.y))
        cross.move(to: CGPoint(x: touch.x, y: touch.y - 10))
        cross.addLine(to: CGPoint(x: touch.x, y: touch.y + 10))
        context.stroke(cross, with: .color(.red), style: StrokeStyle(lineWidth: 1))
    }

    private func drawBitmaps(_ drawn: StickmanUnit, context: inout GraphicsContext, layout: SkeletonLayout, assets: UnitAssets) {
        struct Bone {
            var weight: Int
            var start: CGPoint
            var end: CGPoint
            var asset: UnitAssets.EdgeAsset
        }
        var bones: [Bone] = []
        let name = UnitAssets.removeNumber(drawn.name)
        for edge in drawn.edges {
            let key = UnitAssets.EdgeKey(unitName: name, start: edge.from, end: edge.to, flipped: drawn.flipped)
            guard let asset = assets.getDrawable(key, state: drawn.assetsState) else { continue }
            let from = drawn.point(id: edge.from)
            let to = drawn.point(id: edge.to)
            bones.append(
                Bone(
                    weight: asset.weight,
                    start: CGPoint(x: from.x, y: from.y),
                    end: CGPoint(x: to.x, y: to.y),
                    asset: asset
                )
            )
        }
        bones.sort { $0.weight < $1.weight }
        for bone in bones {
            let angle = atan2(bone.end.y - bone.start.y, bone.end.x - bone.start.x)
            // Unit flipped=true with no flipped PNG (nativeFlipped): Android mirrors
            // the unflipped bitmap (scale y, negate y_offset). Looking up a flipped
            // key and drawing as-is left dino head/torso upside-down.
            let mirror = drawn.flipped && !bone.asset.nativeFlipped
            let yOffset = (mirror ? -bone.asset.yOffset : bone.asset.yOffset) * drawn.scale
            context.drawLayer { ctx in
                ctx.translateBy(
                    x: layout.originX - layout.minX * layout.scale,
                    y: layout.originY - layout.minY * layout.scale
                )
                ctx.scaleBy(x: layout.scale, y: layout.scale)
                ctx.translateBy(x: bone.start.x, y: bone.start.y)
                ctx.rotate(by: Angle(radians: angle))
                ctx.translateBy(x: -bone.start.x, y: -bone.start.y)
                ctx.translateBy(
                    x: bone.start.x + bone.asset.xOffset * drawn.scale,
                    y: bone.start.y + yOffset
                )
                ctx.scaleBy(x: drawn.scale, y: mirror ? -drawn.scale : drawn.scale)
                ctx.draw(
                    Image(decorative: bone.asset.bitmap, scale: 1),
                    at: .zero,
                    anchor: .topLeading
                )
            }
        }
    }

    private func resolvedLayout(size: CGSize) -> SkeletonLayout {
        if let layout, layoutSize == size {
            return layout
        }
        return SkeletonLayout.fit(sceneWidth: sceneWidth, sceneHeight: sceneHeight, in: size)
    }

    private func freezeLayout(in size: CGSize) {
        let fit = SkeletonLayout.fit(sceneWidth: sceneWidth, sceneHeight: sceneHeight, in: size)
        layout = fit
        layoutSize = size
        fitScale = fit.scale
        snapHandlers(to: fit)
    }

    private func handlePinch(focus: CGPoint, factor: CGFloat) {
        guard let current = layout else { return }
        let next = current.pinched(
            around: focus,
            factor: factor,
            minScale: fitScale * 0.6,
            maxScale: fitScale * 6
        )
        layout = next
        snapHandlers(to: next)
    }

    private func snapHandlers(to layout: SkeletonLayout) {
        let centers = unit.handlerCenters(sceneScale: layout.scale)
        handlerMove = centers.move
        handlerRotate = centers.rotate
        handlerScale = centers.scale
    }

    private func placeHandlers(on layout: SkeletonLayout) {
        let centers = unit.handlerCenters(sceneScale: layout.scale)
        handlerMove = centers.move
        handlerRotate = centers.rotate
        handlerScale = centers.scale
        switch dragRef.handler {
        case .move:
            handlerMove = CGPoint(x: dragRef.handlerX, y: dragRef.handlerY)
        case .rotate:
            handlerRotate = CGPoint(x: dragRef.handlerX, y: dragRef.handlerY)
        case .scale:
            handlerScale = CGPoint(x: dragRef.handlerX, y: dragRef.handlerY)
        case nil:
            break
        }
    }

    private func sceneScreenRect(layout: SkeletonLayout) -> CGRect {
        let origin = layout.screenPoint(x: 0, y: 0)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: sceneWidth * layout.scale,
            height: sceneHeight * layout.scale
        )
    }

    private func drawScene(context: inout GraphicsContext, layout: SkeletonLayout) {
        let rect = sceneScreenRect(layout: layout)
        if let name = bgName, name.hasPrefix("usermade:") {
            let origin = layout.screenPoint(x: 0, y: 0)
            context.drawLayer { layer in
                layer.clip(to: Path(rect))
                layer.translateBy(x: origin.x, y: origin.y)
                layer.scaleBy(x: layout.scale, y: layout.scale)
                drawSceneContent(context: &layer)
            }
            return
        }
        if let name = bgName {
            let rgba = HexRGB.parse(name)
            context.fill(
                Path(rect),
                with: .color(Color(red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a))
            )
            return
        }
        context.fill(Path(rect), with: .color(sceneFill))
    }

    private func drawAppliedCamera(context: inout GraphicsContext, layout: SkeletonLayout, clip: Bool) {
        context.drawLayer { layer in
            if clip {
                layer.clip(to: Path(sceneScreenRect(layout: layout)))
            }
            layer.concatenate(cameraMove.canvasTransform(layout: layout))
            layer.drawLayer { bg in
                drawSceneContent(context: &bg)
            }
            for drawn in unitsToDraw {
                drawUnit(drawn, context: &layer, layout: .sceneSpace)
            }
        }
    }

    private func drawCameraWindow(context: inout GraphicsContext, layout: SkeletonLayout) {
        context.stroke(
            Path(sceneScreenRect(layout: layout)),
            with: .color(Self.cameraFrame),
            style: StrokeStyle(lineWidth: 4 * layout.scale, lineCap: .square)
        )
    }

    private func drawSceneBound(context: inout GraphicsContext, layout: SkeletonLayout) {
        let rect = sceneScreenRect(layout: layout)
        context.stroke(
            Path(rect),
            with: .color(Self.sceneBound),
            style: StrokeStyle(lineWidth: 2 * layout.scale, lineCap: .square)
        )
    }

    private func drawSceneContent(context: inout GraphicsContext) {
        let rect = CGRect(x: 0, y: 0, width: sceneWidth, height: sceneHeight)
        if let name = bgName, name.hasPrefix("usermade:") {
            guard let backgrounds else {
                fatalError("SkeletonCanvas missing BackgroundAssets for '\(name)'")
            }
            context.concatenate(bgMove.toTransform())
            context.draw(
                Image(decorative: backgrounds.image(for: name), scale: 1),
                at: .zero,
                anchor: .topLeading
            )
            return
        }
        if let name = bgName {
            let rgba = HexRGB.parse(name)
            context.fill(
                Path(rect),
                with: .color(Color(red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a))
            )
            return
        }
        context.fill(Path(rect), with: .color(sceneFill))
    }

    private func drawCameraRectangle(context: inout GraphicsContext, layout: SkeletonLayout) {
        if cameraMove.isZero {
            return
        }
        let transform = cameraMove.toTransform()
        if transform.a * transform.d - transform.b * transform.c == 0 {
            fatalError("SkeletonCanvas camera transform is not invertible")
        }
        let inverse = transform.inverted()
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: sceneWidth, y: 0),
            CGPoint(x: sceneWidth, y: sceneHeight),
            CGPoint(x: 0, y: sceneHeight)
        ].map { point -> CGPoint in
            let mapped = point.applying(inverse)
            return layout.screenPoint(x: mapped.x, y: mapped.y)
        }
        var path = Path()
        path.move(to: corners[0])
        path.addLine(to: corners[1])
        path.addLine(to: corners[2])
        path.addLine(to: corners[3])
        path.closeSubpath()
        context.stroke(
            path,
            with: .color(Self.cameraFrame),
            style: StrokeStyle(lineWidth: 4 * layout.scale, lineCap: .square)
        )
    }

    private func drawHandlers(context: inout GraphicsContext, layout: SkeletonLayout) {
        guard mode != .editor || selectedUnitName.wrappedValue != nil else { return }
        if dragRef.handler != nil || dragRef.nodeId != nil { return }
        let side = CGFloat(HandlerArtwork.move.width) / UIScreen.main.scale
        context.withCGContext { cg in
            for handle in visibleHandlers() {
                let icon: CGImage
                switch handle.kind {
                case .move: icon = HandlerArtwork.move
                case .rotate: icon = HandlerArtwork.rotate
                case .scale: icon = HandlerArtwork.scale
                }
                let center = layout.screenPoint(x: handle.x, y: handle.y)
                cg.draw(
                    icon,
                    in: CGRect(
                        x: center.x - side / 2,
                        y: center.y - side / 2,
                        width: side,
                        height: side
                    )
                )
            }
        }
    }

    private func visibleHandlers() -> [(kind: ItemHandlerKind, x: CGFloat, y: CGFloat)] {
        [
            (.move, handlerMove.x, handlerMove.y),
            (.rotate, handlerRotate.x, handlerRotate.y),
            (.scale, handlerScale.x, handlerScale.y)
        ]
    }

    private func handleDrag(at location: CGPoint, size: CGSize, began: Bool) {
        touchScreen = location
        let current = resolvedLayout(size: size)
        if mode == .skeleton, boneCreateHoldFlag {
            handleBoneCreate(at: location, layout: current, began: began)
            return
        }
        if began {
            if mode == .editor, selectedUnitName.wrappedValue != nil,
               let handle = hitHandler(at: location, layout: current) {
                dragRef.handler = handle.kind
                dragRef.handlerX = handle.x
                dragRef.handlerY = handle.y
                dragRef.nodeId = nil
                dragRef.panning = false
                if handle.kind == .rotate {
                    dragRef.rotateDiff = unit.handlerRotateDiff(handler: CGPoint(x: handle.x, y: handle.y))
                } else if handle.kind == .scale {
                    let base = unit.basePoint()
                    let dist = hypot(handle.x - base.x, handle.y - base.y)
                    if dist <= 0 {
                        fatalError("SkeletonCanvas scale handler sits on the base")
                    }
                    dragRef.scalePivotDist = dist
                    dragRef.scaleStart = unit.scale
                }
            } else {
                dragRef.handler = nil
                if mode == .editor, let hit = hitAnyUnit(at: location, layout: current) {
                    selectedUnitName.wrappedValue = hit.name
                    dragRef.nodeId = hit.pointId
                    let graph = current.graphPoint(screen: location)
                    let node = hit.unit.point(id: hit.pointId)
                    dragRef.touchOffsetX = graph.x - node.x
                    dragRef.touchOffsetY = graph.y - node.y
                } else {
                    dragRef.nodeId = hitNode(at: location, layout: current)
                    if let id = dragRef.nodeId {
                        let graph = current.graphPoint(screen: location)
                        let node = unit.point(id: id)
                        dragRef.touchOffsetX = graph.x - node.x
                        dragRef.touchOffsetY = graph.y - node.y
                    } else {
                        dragRef.touchOffsetX = 0
                        dragRef.touchOffsetY = 0
                    }
                }
                dragRef.panning = dragRef.nodeId == nil
                if mode == .skeleton {
                    selectedPointId.wrappedValue = dragRef.nodeId
                }
            }
            dragRef.lastScreen = location
        }
        if let kind = dragRef.handler {
            let graph = current.graphPoint(screen: location)
            let dx = graph.x - dragRef.handlerX
            let dy = graph.y - dragRef.handlerY
            dragRef.handlerX = graph.x
            dragRef.handlerY = graph.y
            switch kind {
            case .move:
                unit.translateAll(dx: dx, dy: dy)
            case .rotate:
                unit.rotateToHandler(
                    handler: CGPoint(x: dragRef.handlerX, y: dragRef.handlerY),
                    constDiff: dragRef.rotateDiff
                )
            case .scale:
                let base = unit.basePoint()
                let dist = hypot(dragRef.handlerX - base.x, dragRef.handlerY - base.y)
                if dist <= 1 { return }
                unit.scaleAt(
                    pivotX: base.x,
                    pivotY: base.y,
                    target: dragRef.scaleStart * dist / dragRef.scalePivotDist
                )
            }
            placeHandlers(on: current)
            return
        }
        if let id = dragRef.nodeId {
            let graphPoint = current.graphPoint(screen: location)
            let destX = graphPoint.x - dragRef.touchOffsetX
            let destY = graphPoint.y - dragRef.touchOffsetY
            if mode == .skeleton {
                unit.movePointAndDescendants(id: id, destX: destX, destY: destY)
            } else {
                unit.drag(id: id, destX: destX, destY: destY)
            }
            snapHandlers(to: current)
            return
        }
        guard dragRef.panning, let last = dragRef.lastScreen else { return }
        layout = current.panned(dx: location.x - last.x, dy: location.y - last.y)
        dragRef.lastScreen = location
    }

    private func handleEmptyDoubleTap(at location: CGPoint, size: CGSize) {
        guard mode == .editor else { return }
        let current = resolvedLayout(size: size)
        if hitAnyUnit(at: location, layout: current) == nil {
            selectedUnitName.wrappedValue = nil
            endTouch()
        }
    }

    private func endTouch() {
        if mode == .skeleton, boneCreateHoldFlag || boneCreateStartId != nil {
            commitBoneCreate()
            touchScreen = nil
            return
        }
        touchScreen = nil
        dragRef.nodeId = nil
        dragRef.handler = nil
        dragRef.lastScreen = nil
        dragRef.panning = false
        dragRef.touchOffsetX = 0
        dragRef.touchOffsetY = 0
        if let current = layout {
            snapHandlers(to: current)
        }
    }

    private func handleBoneCreate(at location: CGPoint, layout: SkeletonLayout, began: Bool) {
        let graph = layout.graphPoint(screen: location)
        if began {
            boneCreateStartId = hitNode(
                at: location,
                layout: layout,
                radius: Self.boneCreateCapture * layout.scale
            )
            if let id = boneCreateStartId {
                let start = unit.point(id: id)
                boneCreateEnd = CGPoint(x: start.x, y: start.y)
            } else {
                boneCreateEnd = nil
            }
            return
        }
        if boneCreateStartId != nil {
            boneCreateEnd = graph
        }
    }

    private func commitBoneCreate() {
        defer { resetBoneCreateGesture() }
        guard let startId = boneCreateStartId, let end = boneCreateEnd else {
            return
        }
        let start = unit.point(id: startId)
        let drag = hypot(end.x - start.x, end.y - start.y)
        // Android BONE_CREATE_MIN_DRAG is in unscaled item units; iOS points are already scaled.
        let minDrag = Self.boneCreateMinDrag * max(unit.scale, 0.01)
        if drag < minDrag {
            return
        }
        let newId = unit.addPointWithEdge(parentId: startId, destX: end.x, destY: end.y)
        selectedPointId.wrappedValue = newId
    }

    private func resetBoneCreateGesture() {
        boneCreateStartId = nil
        boneCreateEnd = nil
    }

    private func hitHandler(at location: CGPoint, layout: SkeletonLayout) -> (kind: ItemHandlerKind, x: CGFloat, y: CGFloat)? {
        var best: (kind: ItemHandlerKind, x: CGFloat, y: CGFloat)?
        var bestDist = Self.handlerHitRadius
        for handle in visibleHandlers() {
            let center = layout.screenPoint(x: handle.x, y: handle.y)
            let dist = hypot(location.x - center.x, location.y - center.y)
            if dist <= bestDist {
                bestDist = dist
                best = handle
            }
        }
        return best
    }

    private func hitNode(at location: CGPoint, layout: SkeletonLayout, radius: CGFloat = Self.hitRadius) -> Int? {
        hitAnyUnit(at: location, layout: layout, radius: radius, in: [unit])?.pointId
    }

    /// First node within `radius` in front-to-back draw order.
    private func hitAnyUnit(
        at location: CGPoint,
        layout: SkeletonLayout,
        radius: CGFloat = Self.hitRadius,
        in candidates: [StickmanUnit]? = nil
    ) -> (name: String, pointId: Int, unit: StickmanUnit)? {
        let pool = candidates ?? (frameUnits.isEmpty ? [unit] : frameUnits)
        for drawn in pool.sorted(by: {
            if $0.arrange != $1.arrange { return $0.arrange > $1.arrange }
            return $0.name > $1.name
        }) {
            for point in drawn.points {
                let center = layout.screenPoint(x: point.x, y: point.y)
                let dist = hypot(location.x - center.x, location.y - center.y)
                if dist <= radius {
                    return (drawn.name, point.id, drawn)
                }
            }
        }
        return nil
    }
}

private struct CameraTouchOverlay: UIViewRepresentable {
    var currentIndex: Int
    var cameraMove: PictureMove
    var layoutScale: CGFloat
    var windowCenter: CGPoint
    var onChange: (PictureMove) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch))
        pinch.delegate = context.coordinator
        let rotate = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotate))
        rotate.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(rotate)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.currentIndex != currentIndex {
            coordinator.working = nil
            coordinator.currentIndex = currentIndex
        }
        coordinator.cameraMove = cameraMove
        coordinator.layoutScale = layoutScale
        coordinator.windowCenter = windowCenter
        coordinator.onChange = onChange
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        static let minScale: CGFloat = 0.2
        static let maxScale: CGFloat = 4.4
        static let rotationSnap: CGFloat = 5

        var currentIndex = 0
        var cameraMove = PictureMove.identity
        var layoutScale: CGFloat = 1
        var windowCenter = CGPoint.zero
        var onChange: (PictureMove) -> Void = { _ in }
        var working: PictureMove?

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            (gestureRecognizer is UIPinchGestureRecognizer && other is UIRotationGestureRecognizer)
                || (gestureRecognizer is UIRotationGestureRecognizer && other is UIPinchGestureRecognizer)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                beginSession()
            case .changed:
                beginSession()
                if layoutScale <= 0 {
                    fatalError("CameraTouchOverlay layoutScale is \(layoutScale)")
                }
                let delta = gesture.translation(in: gesture.view)
                gesture.setTranslation(.zero, in: gesture.view)
                mutate {
                    $0.x += delta.x / layoutScale
                    $0.y += delta.y / layoutScale
                }
                publish()
            case .ended, .cancelled, .failed:
                if working != nil {
                    publish()
                }
                endIfIdle(gesture)
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                beginSession()
                gesture.scale = 1
            case .changed, .ended, .cancelled, .failed:
                beginSession()
                let factor = gesture.scale
                gesture.scale = 1
                if factor <= 0 {
                    fatalError("CameraTouchOverlay pinch factor is \(factor)")
                }
                mutate { move in
                    let oldScale = move.scale
                    let newScale = min(max(oldScale * sqrt(factor), Self.minScale), Self.maxScale)
                    let f = newScale / oldScale
                    move.scale = newScale
                    move.x = f * move.x + (1 - f) * windowCenter.x
                    move.y = f * move.y + (1 - f) * windowCenter.y
                }
                publish()
                if gesture.state != .changed {
                    endIfIdle(gesture)
                }
            default:
                break
            }
        }

        @objc func handleRotate(_ gesture: UIRotationGestureRecognizer) {
            switch gesture.state {
            case .began:
                beginSession()
                gesture.rotation = 0
            case .changed, .ended, .cancelled, .failed:
                beginSession()
                let degrees = gesture.rotation * 180 / .pi
                gesture.rotation = 0
                mutate { move in
                    move.rotate = Self.wrapDegrees(move.rotate + degrees)
                }
                publish()
                if gesture.state != .changed {
                    endIfIdle(gesture)
                }
            default:
                break
            }
        }

        private func beginSession() {
            if working == nil {
                working = cameraMove
            }
        }

        private func mutate(_ body: (inout PictureMove) -> Void) {
            guard var move = working else {
                fatalError("CameraTouchOverlay mutate with no working move")
            }
            body(&move)
            working = move
        }

        private func publish() {
            guard let move = working else {
                fatalError("CameraTouchOverlay publish with no working move")
            }
            onChange(
                PictureMove(
                    scale: move.scale,
                    rotate: Self.snapRotation(move.rotate),
                    x: move.x,
                    y: move.y
                )
            )
        }

        private func endIfIdle(_ gesture: UIGestureRecognizer) {
            guard let recognizers = gesture.view?.gestureRecognizers else {
                working = nil
                return
            }
            let active = recognizers.contains {
                $0.state == .began || $0.state == .changed
            }
            if !active {
                working = nil
            }
        }

        static func wrapDegrees(_ degrees: CGFloat) -> CGFloat {
            if degrees > 180 {
                return degrees - 360
            }
            if degrees < -180 {
                return degrees + 360
            }
            return degrees
        }

        static func snapRotation(_ degrees: CGFloat) -> CGFloat {
            var snapped = (degrees / Self.rotationSnap).rounded() * Self.rotationSnap
            if snapped > 180 {
                snapped -= 360
            }
            if snapped < -180 {
                snapped += 360
            }
            return snapped
        }
    }
}

private struct SkeletonTouchOverlay: UIViewRepresentable {
    var useRawTouches: Bool = false
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void
    var onDoubleTap: (CGPoint) -> Void = { _ in }
    var onPinchBegan: () -> Void
    var onPinch: (CGPoint, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TouchForwardView {
        let view = TouchForwardView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.coordinator = context.coordinator
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        view.pan = pan
        view.addGestureRecognizer(pan)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        view.addGestureRecognizer(doubleTap)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch))
        view.addGestureRecognizer(pinch)
        context.coordinator.apply(useRawTouches: useRawTouches, to: view)
        return view
    }

    func updateUIView(_ uiView: TouchForwardView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onDoubleTap = onDoubleTap
        context.coordinator.onPinchBegan = onPinchBegan
        context.coordinator.onPinch = onPinch
        context.coordinator.apply(useRawTouches: useRawTouches, to: uiView)
    }

    final class Coordinator: NSObject {
        var onBegan: (CGPoint) -> Void = { _ in }
        var onChanged: (CGPoint) -> Void = { _ in }
        var onEnded: (CGPoint) -> Void = { _ in }
        var onDoubleTap: (CGPoint) -> Void = { _ in }
        var onPinchBegan: () -> Void = {}
        var onPinch: (CGPoint, CGFloat) -> Void = { _, _ in }
        var useRawTouches = false
        private var rawActive = false

        func apply(useRawTouches: Bool, to view: TouchForwardView) {
            self.useRawTouches = useRawTouches
            view.pan?.isEnabled = !useRawTouches
            view.forwardsTouches = useRawTouches
        }

        func rawBegan(_ point: CGPoint) {
            guard useRawTouches else { return }
            rawActive = true
            onBegan(point)
        }

        func rawChanged(_ point: CGPoint) {
            guard useRawTouches, rawActive else { return }
            onChanged(point)
        }

        func rawEnded(_ point: CGPoint) {
            guard useRawTouches, rawActive else { return }
            rawActive = false
            onEnded(point)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            onDoubleTap(gesture.location(in: gesture.view))
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            if useRawTouches { return }
            let point = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began:
                onBegan(point)
            case .changed:
                onChanged(point)
            case .ended, .cancelled, .failed:
                onEnded(point)
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            let focus = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began:
                if rawActive {
                    rawActive = false
                    onEnded(focus)
                }
                onPinchBegan()
                onPinch(focus, 1)
            case .changed:
                onPinch(focus, gesture.scale)
                gesture.scale = 1
            case .ended, .cancelled, .failed:
                onPinch(focus, gesture.scale)
                gesture.scale = 1
            default:
                break
            }
        }
    }
}

/// Delivers touchesBegan immediately (no pan-threshold delay) when bone-create needs it.
private final class TouchForwardView: UIView {
    weak var coordinator: SkeletonTouchOverlay.Coordinator?
    weak var pan: UIPanGestureRecognizer?
    var forwardsTouches = false
    private var tracking: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard forwardsTouches, tracking == nil, let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }
        tracking = touch
        coordinator?.rawBegan(touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard forwardsTouches, let tracking, touches.contains(tracking) else {
            super.touchesMoved(touches, with: event)
            return
        }
        coordinator?.rawChanged(tracking.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard forwardsTouches, let tracking, touches.contains(tracking) else {
            super.touchesEnded(touches, with: event)
            return
        }
        let point = tracking.location(in: self)
        self.tracking = nil
        coordinator?.rawEnded(point)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard forwardsTouches, let tracking, touches.contains(tracking) else {
            super.touchesCancelled(touches, with: event)
            return
        }
        let point = tracking.location(in: self)
        self.tracking = nil
        coordinator?.rawEnded(point)
    }
}
