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

struct SkeletonCanvas: View {
    static let color = Color(red: 1, green: 0x71 / 255, blue: 0)
    static let edgeWidth: CGFloat = 1
    static let nodeRadius: CGFloat = 3
    static let baseNodeRadius: CGFloat = 4.4
    static let hitRadius: CGFloat = 28
    static let handlerHitRadius: CGFloat = 32
    static let checkerCell: CGFloat = 16
    static let checkerLight = Color.white
    static let checkerGray = Color(white: 0.85)
    static let sceneFill = Color(white: 0.85)

    @Binding var unit: StickmanUnit
    var assets: UnitAssets?
    var backgrounds: BackgroundAssets?
    var bgName: String?
    var bgMove: PictureMove = .identity
    var sceneWidth: CGFloat
    var sceneHeight: CGFloat
    var currentIndex: Int = 0
    var sceneFill: Color = Self.sceneFill
    var interactive: Bool = true
    var showSkeleton: Bool = true
    @State private var layout: SkeletonLayout?
    @State private var layoutSize: CGSize = .zero
    @State private var fitScale: CGFloat = 1
    @State private var handlerMove = CGPoint.zero
    @State private var handlerRotate = CGPoint.zero
    @State private var handlerScale = CGPoint.zero
    @State private var touchScreen: CGPoint?
    @State private var dragRef = DragRef()

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
            Canvas { context, size in
                drawChecker(context: &context, size: size)
                let layout = resolvedLayout(size: size)
                drawScene(context: &context, layout: layout)
                drawUnit(context: &context, layout: layout)
                if interactive {
                    drawHandlers(context: &context, layout: layout)
                    drawTouchPoint(context: &context)
                }
            }
            .overlay {
                if interactive {
                    SkeletonTouchOverlay(
                        onBegan: { handleDrag(at: $0, size: proxy.size, began: true) },
                        onChanged: { handleDrag(at: $0, size: proxy.size, began: false) },
                        onEnded: { _ in endTouch() },
                        onPinchBegan: { endTouch() },
                        onPinch: { handlePinch(focus: $0, factor: $1) }
                    )
                }
            }
            .onAppear { freezeLayout(in: proxy.size) }
            .onChange(of: proxy.size) { _, newSize in
                freezeLayout(in: newSize)
            }
            .onChange(of: currentIndex) { _, _ in
                if let current = layout {
                    snapHandlers(to: current)
                }
            }
        }
    }

    private func drawUnit(context: inout GraphicsContext, layout: SkeletonLayout) {
        if let assets {
            if unit.alpha < 1 {
                context.drawLayer { layer in
                    layer.opacity = Double(unit.alpha)
                    layer.drawLayer { opaque in
                        drawBitmaps(context: &opaque, layout: layout, assets: assets)
                    }
                }
            } else {
                drawBitmaps(context: &context, layout: layout, assets: assets)
            }
        }
        if showSkeleton {
            drawSkeleton(context: &context, layout: layout)
            if FeatureFlags.debugDrawTouchCapture {
                drawTouchCapture(context: &context, layout: layout)
            }
        }
    }

    private func drawSkeleton(context: inout GraphicsContext, layout: SkeletonLayout) {
        for edge in unit.edges {
            let from = unit.point(id: edge.from)
            let to = unit.point(id: edge.to)
            var path = Path()
            path.move(to: layout.screenPoint(x: from.x, y: from.y))
            path.addLine(to: layout.screenPoint(x: to.x, y: to.y))
            context.stroke(
                path,
                with: .color(Self.color),
                style: StrokeStyle(lineWidth: Self.edgeWidth, lineCap: .butt)
            )
        }
        for point in unit.points {
            let center = layout.screenPoint(x: point.x, y: point.y)
            let radius = point.isBase ? Self.baseNodeRadius : Self.nodeRadius
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(Self.color))
        }
    }

    private func drawTouchCapture(context: inout GraphicsContext, layout: SkeletonLayout) {
        let radius = Self.hitRadius
        let color = Color.cyan.opacity(180 / 255)
        for point in unit.points {
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

    private func drawBitmaps(context: inout GraphicsContext, layout: SkeletonLayout, assets: UnitAssets) {
        struct Bone {
            var weight: Int
            var start: CGPoint
            var end: CGPoint
            var asset: UnitAssets.EdgeAsset
        }
        var bones: [Bone] = []
        let name = UnitAssets.removeNumber(unit.name)
        for edge in unit.edges {
            let key = UnitAssets.EdgeKey(unitName: name, start: edge.from, end: edge.to)
            guard let asset = assets.getDrawable(key, state: UnitAssets.stateDefault) else { continue }
            let from = unit.point(id: edge.from)
            let to = unit.point(id: edge.to)
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
                    x: bone.start.x + bone.asset.xOffset * unit.scale,
                    y: bone.start.y + bone.asset.yOffset * unit.scale
                )
                ctx.scaleBy(x: unit.scale, y: unit.scale)
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

    private func drawScene(context: inout GraphicsContext, layout: SkeletonLayout) {
        let origin = layout.screenPoint(x: 0, y: 0)
        let rect = CGRect(
            x: origin.x,
            y: origin.y,
            width: sceneWidth * layout.scale,
            height: sceneHeight * layout.scale
        )
        if let name = bgName, name.hasPrefix("usermade:") {
            guard let backgrounds else {
                fatalError("SkeletonCanvas missing BackgroundAssets for '\(name)'")
            }
            let image = backgrounds.image(for: name)
            context.drawLayer { layer in
                layer.clip(to: Path(rect))
                layer.translateBy(x: origin.x, y: origin.y)
                layer.scaleBy(x: layout.scale, y: layout.scale)
                layer.concatenate(bgMove.toTransform())
                layer.draw(Image(decorative: image, scale: 1), at: .zero, anchor: .topLeading)
            }
            return
        }
        if let name = bgName {
            let rgb = HexRGB.parse(name)
            context.fill(
                Path(rect),
                with: .color(Color(red: rgb.0, green: rgb.1, blue: rgb.2))
            )
            return
        }
        context.fill(Path(rect), with: .color(sceneFill))
    }

    private func drawChecker(context: inout GraphicsContext, size: CGSize) {
        let cell = Self.checkerCell
        var row = 0
        var y: CGFloat = 0
        while y < size.height {
            var col = 0
            var x: CGFloat = 0
            while x < size.width {
                let color = (row + col).isMultiple(of: 2) ? Self.checkerLight : Self.checkerGray
                context.fill(
                    Path(CGRect(x: x, y: y, width: cell, height: cell)),
                    with: .color(color)
                )
                x += cell
                col += 1
            }
            y += cell
            row += 1
        }
    }

    private func drawHandlers(context: inout GraphicsContext, layout: SkeletonLayout) {
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
        if began {
            if let handle = hitHandler(at: location, layout: current) {
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
                dragRef.nodeId = hitNode(at: location, layout: current)
                dragRef.panning = dragRef.nodeId == nil
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
            unit.drag(
                id: id,
                destX: graphPoint.x - dragRef.touchOffsetX,
                destY: graphPoint.y - dragRef.touchOffsetY
            )
            snapHandlers(to: current)
            return
        }
        guard dragRef.panning, let last = dragRef.lastScreen else { return }
        layout = current.panned(dx: location.x - last.x, dy: location.y - last.y)
        dragRef.lastScreen = location
    }

    private func endTouch() {
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

    private func hitNode(at location: CGPoint, layout: SkeletonLayout) -> Int? {
        var bestId: Int?
        var bestDist = Self.hitRadius
        for point in unit.points {
            let center = layout.screenPoint(x: point.x, y: point.y)
            let dist = hypot(location.x - center.x, location.y - center.y)
            if dist <= bestDist {
                bestDist = dist
                bestId = point.id
            }
        }
        return bestId
    }
}

private struct SkeletonTouchOverlay: UIViewRepresentable {
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void
    var onPinchBegan: () -> Void
    var onPinch: (CGPoint, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch))
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onPinchBegan = onPinchBegan
        context.coordinator.onPinch = onPinch
    }

    final class Coordinator: NSObject {
        var onBegan: (CGPoint) -> Void = { _ in }
        var onChanged: (CGPoint) -> Void = { _ in }
        var onEnded: (CGPoint) -> Void = { _ in }
        var onPinchBegan: () -> Void = {}
        var onPinch: (CGPoint, CGFloat) -> Void = { _, _ in }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
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
