import CoreGraphics
import CoreImage
import SwiftUI
import UIKit

public struct BonePaperFrameInput {
    public let state: Int
    public let weight: Int
    public let source: CGImage?
    public let buffer: CGImage?
    public let xOffset: CGFloat
    public let yOffset: CGFloat
    public let drawingConfig: BonePaperDrawingConfig

    public init(
        state: Int,
        weight: Int = 1,
        source: CGImage?,
        buffer: CGImage? = nil,
        xOffset: CGFloat = 0,
        yOffset: CGFloat = 0,
        drawingConfig: BonePaperDrawingConfig = BonePaperDrawingConfig()
    ) {
        self.state = state
        self.weight = max(1, weight)
        self.source = source
        self.buffer = buffer
        self.xOffset = xOffset
        self.yOffset = yOffset
        self.drawingConfig = drawingConfig
    }
}

public struct BonePaperFrameSnapshot: Identifiable {
    public var id: Int { state }
    public var state: Int
    public var weight: Int
    public var buffer: CGImage
    public var width: Int
    public var height: Int
    public var originX: Int
    public var originY: Int
    public var extraLeft: Int
    public var extraTop: Int
    public var baseXOffset: CGFloat
    public var baseYOffset: CGFloat
    public var drawingConfig: BonePaperDrawingConfig
    public var thumbnail: CGImage?
}

public struct BonePaperFrameExport {
    public let state: Int
    public let weight: Int
    public let baseXOffset: CGFloat
    public let baseYOffset: CGFloat
    public let export: BonePaperExport
}

public final class BonePaperFramesSession: ObservableObject {
    @Published public private(set) var frames: [BonePaperFrameSnapshot] = []
    @Published public private(set) var selectedState: Int = 0
    @Published public private(set) var previousFrameOnion: CGImage? = nil

    private let emptyWidth: Int
    private let emptyHeight: Int
    private let emptyXOffset: CGFloat
    private let emptyYOffset: CGFloat

    public init(
        inputs: [BonePaperFrameInput],
        initialState: Int = 0,
        defaultWidth: Int = BonePaperDocument.defaultSide,
        defaultHeight: Int = BonePaperDocument.defaultSide,
        defaultXOffset: CGFloat = 0,
        defaultYOffset: CGFloat = 0
    ) {
        let sorted = inputs.sorted { $0.state < $1.state }
        let firstSource = sorted.first?.source
        self.emptyWidth = firstSource?.width ?? defaultWidth
        self.emptyHeight = firstSource?.height ?? defaultHeight
        self.emptyXOffset = sorted.first?.xOffset ?? defaultXOffset
        self.emptyYOffset = sorted.first?.yOffset ?? defaultYOffset

        if sorted.isEmpty {
            let w = emptyWidth
            let h = emptyHeight
            let ox = (BonePaperDocument.maxSide - w) / 2
            let oy = (BonePaperDocument.maxSide - h) / 2
            let buf = BonePaperDocument.materializeBuffer(width: w, height: h, source: nil, buffer: nil)
            self.frames = [
                BonePaperFrameSnapshot(
                    state: 0,
                    weight: 1,
                    buffer: buf,
                    width: w,
                    height: h,
                    originX: ox,
                    originY: oy,
                    extraLeft: 0,
                    extraTop: 0,
                    baseXOffset: emptyXOffset,
                    baseYOffset: emptyYOffset,
                    drawingConfig: BonePaperToolStore.fallbackConfig,
                    thumbnail: Self.makeThumbnail(from: buf)
                )
            ]
            self.selectedState = 0
            return
        }

        var mappedIndex = 0
        var built: [BonePaperFrameSnapshot] = []
        for (idx, item) in sorted.enumerated() {
            if item.state == initialState {
                mappedIndex = idx
            }
            let w = item.source?.width ?? emptyWidth
            let h = item.source?.height ?? emptyHeight
            let ox = (BonePaperDocument.maxSide - w) / 2
            let oy = (BonePaperDocument.maxSide - h) / 2
            let buf = BonePaperDocument.materializeBuffer(
                width: w,
                height: h,
                source: item.source,
                buffer: item.buffer
            )
            built.append(
                BonePaperFrameSnapshot(
                    state: idx,
                    weight: max(1, item.weight),
                    buffer: buf,
                    width: w,
                    height: h,
                    originX: ox,
                    originY: oy,
                    extraLeft: 0,
                    extraTop: 0,
                    baseXOffset: item.xOffset,
                    baseYOffset: item.yOffset,
                    drawingConfig: item.drawingConfig.sanitized(),
                    thumbnail: Self.makeThumbnail(from: buf)
                )
            )
        }
        self.frames = built
        self.selectedState = min(max(mappedIndex, 0), built.count - 1)
        updatePreviousFrameOnion()
    }

    public var activeSnapshot: BonePaperFrameSnapshot {
        frames[selectedState]
    }

    public func syncActiveFrame(from document: BonePaperDocument, drawingConfig: BonePaperDrawingConfig) {
        guard frames.indices.contains(selectedState) else { return }
        let committed = document.snapshotBuffer()
        frames[selectedState].buffer = committed
        frames[selectedState].width = document.width
        frames[selectedState].height = document.height
        frames[selectedState].originX = document.originX
        frames[selectedState].originY = document.originY
        frames[selectedState].extraLeft = document.extraLeft
        frames[selectedState].extraTop = document.extraTop
        frames[selectedState].drawingConfig = drawingConfig
        frames[selectedState].thumbnail = Self.makeThumbnail(from: committed)
    }

    public func refreshActiveThumbnail(from preview: CGImage) {
        guard frames.indices.contains(selectedState) else { return }
        frames[selectedState].thumbnail = Self.makeThumbnail(from: preview)
    }

    @discardableResult
    public func selectFrame(
        _ state: Int,
        into document: BonePaperDocument,
        currentConfig: BonePaperDrawingConfig
    ) -> BonePaperDrawingConfig {
        guard frames.indices.contains(state) else { return currentConfig }
        if state == selectedState {
            return currentConfig
        }
        syncActiveFrame(from: document, drawingConfig: currentConfig)
        selectedState = state
        updatePreviousFrameOnion()
        let target = frames[state]
        document.loadFrameBuffer(
            target.buffer,
            width: target.width,
            height: target.height,
            originX: target.originX,
            originY: target.originY,
            extraLeft: target.extraLeft,
            extraTop: target.extraTop
        )
        return target.drawingConfig
    }

    @discardableResult
    public func createEmptyFrame(
        afterSyncing document: BonePaperDocument,
        currentConfig: BonePaperDrawingConfig
    ) -> BonePaperDrawingConfig {
        syncActiveFrame(from: document, drawingConfig: currentConfig)
        let newState = frames.count
        let w = emptyWidth
        let h = emptyHeight
        let ox = (BonePaperDocument.maxSide - w) / 2
        let oy = (BonePaperDocument.maxSide - h) / 2
        let blank = BonePaperDocument.materializeBuffer(width: w, height: h, source: nil, buffer: nil)
        let snapshot = BonePaperFrameSnapshot(
            state: newState,
            weight: 1,
            buffer: blank,
            width: w,
            height: h,
            originX: ox,
            originY: oy,
            extraLeft: 0,
            extraTop: 0,
            baseXOffset: emptyXOffset,
            baseYOffset: emptyYOffset,
            drawingConfig: currentConfig,
            thumbnail: Self.makeThumbnail(from: blank)
        )
        frames.append(snapshot)
        selectedState = newState
        updatePreviousFrameOnion()
        document.loadFrameBuffer(
            snapshot.buffer,
            width: snapshot.width,
            height: snapshot.height,
            originX: snapshot.originX,
            originY: snapshot.originY,
            extraLeft: snapshot.extraLeft,
            extraTop: snapshot.extraTop
        )
        return snapshot.drawingConfig
    }

    @discardableResult
    public func copyFrame(
        state: Int,
        afterSyncing document: BonePaperDocument,
        currentConfig: BonePaperDrawingConfig
    ) -> BonePaperDrawingConfig {
        syncActiveFrame(from: document, drawingConfig: currentConfig)
        guard frames.indices.contains(state) else { return currentConfig }
        let source = frames[state]
        let newState = frames.count
        let copiedBuffer = source.buffer.copy() ?? source.buffer
        let snapshot = BonePaperFrameSnapshot(
            state: newState,
            weight: source.weight,
            buffer: copiedBuffer,
            width: source.width,
            height: source.height,
            originX: source.originX,
            originY: source.originY,
            extraLeft: source.extraLeft,
            extraTop: source.extraTop,
            baseXOffset: source.baseXOffset,
            baseYOffset: source.baseYOffset,
            drawingConfig: source.drawingConfig,
            thumbnail: source.thumbnail
        )
        frames.append(snapshot)
        selectedState = newState
        updatePreviousFrameOnion()
        document.loadFrameBuffer(
            snapshot.buffer,
            width: snapshot.width,
            height: snapshot.height,
            originX: snapshot.originX,
            originY: snapshot.originY,
            extraLeft: snapshot.extraLeft,
            extraTop: snapshot.extraTop
        )
        return snapshot.drawingConfig
    }

    @discardableResult
    public func deleteFrame(
        state: Int,
        into document: BonePaperDocument,
        currentConfig: BonePaperDrawingConfig
    ) -> BonePaperDrawingConfig {
        guard frames.count > 1, frames.indices.contains(state) else { return currentConfig }
        syncActiveFrame(from: document, drawingConfig: currentConfig)
        let deletingActive = (state == selectedState)
        frames.remove(at: state)
        for idx in frames.indices {
            frames[idx].state = idx
        }
        if state < selectedState {
            selectedState -= 1
        } else if selectedState >= frames.count {
            selectedState = frames.count - 1
        }
        updatePreviousFrameOnion()
        let target = frames[selectedState]
        if deletingActive {
            document.loadFrameBuffer(
                target.buffer,
                width: target.width,
                height: target.height,
                originX: target.originX,
                originY: target.originY,
                extraLeft: target.extraLeft,
                extraTop: target.extraTop
            )
        }
        return target.drawingConfig
    }

    public func exportAll(
        syncing document: BonePaperDocument,
        currentConfig: BonePaperDrawingConfig
    ) -> [BonePaperFrameExport] {
        syncActiveFrame(from: document, drawingConfig: currentConfig)
        return frames.map { frame in
            let exported = BonePaperDocument.exportCommittedBuffer(
                buffer: frame.buffer,
                width: frame.width,
                height: frame.height,
                extraLeft: frame.extraLeft,
                extraTop: frame.extraTop,
                drawingConfig: frame.drawingConfig
            )
            return BonePaperFrameExport(
                state: frame.state,
                weight: frame.weight,
                baseXOffset: frame.baseXOffset,
                baseYOffset: frame.baseYOffset,
                export: exported
            )
        }
    }

    static func makeThumbnail(from image: CGImage, maxSide: Int = 112) -> CGImage? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }
        let scale = min(1.0, Double(maxSide) / Double(max(w, h)))
        let outW = max(1, Int((Double(w) * scale).rounded()))
        let outH = max(1, Int((Double(h) * scale).rounded()))
        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: outW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        return ctx.makeImage() ?? image
    }

    private func updatePreviousFrameOnion() {
        guard selectedState > 0,
              frames.indices.contains(selectedState),
              frames.indices.contains(selectedState - 1) else {
            previousFrameOnion = nil
            return
        }
        let active = frames[selectedState]
        let prev = frames[selectedState - 1]
        previousFrameOnion = Self.renderPreviousFrameOnion(previous: prev, active: active)
    }

    private static let onionCIContext = CIContext(options: nil)

    private static func renderPreviousFrameOnion(
        previous: BonePaperFrameSnapshot,
        active: BonePaperFrameSnapshot
    ) -> CGImage? {
        let worldSize = BonePaperDocument.maxSide
        let activeStartX = CGFloat(active.originX + active.extraLeft) - active.baseXOffset
        let activeStartY = CGFloat(active.originY + active.extraTop) - active.baseYOffset
        let drawX = activeStartX + previous.baseXOffset - CGFloat(previous.extraLeft)
        let drawY = activeStartY + previous.baseYOffset - CGFloat(previous.extraTop)
        let drawW = CGFloat(previous.width)
        let drawH = CGFloat(previous.height)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let side = CGFloat(worldSize)
        let raster = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIImage(cgImage: previous.buffer).draw(
                in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH)
            )
        }
        guard let cgRaster = raster.cgImage else {
            return nil
        }
        let input = CIImage(cgImage: cgRaster)
        guard let saturate = CIFilter(name: "CIColorControls") else {
            fatalError("BonePaperFramesSession missing CIColorControls")
        }
        saturate.setValue(input, forKey: kCIInputImageKey)
        saturate.setValue(0, forKey: kCIInputSaturationKey)
        guard let gray = saturate.outputImage else {
            return nil
        }
        guard let matrix = CIFilter(name: "CIColorMatrix") else {
            fatalError("BonePaperFramesSession missing CIColorMatrix")
        }
        matrix.setValue(gray, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: 0.2, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: 0.2, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0.2, w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0.85), forKey: "inputAVector")
        matrix.setValue(CIVector(x: 0.8, y: 0.8, z: 0.8, w: 0), forKey: "inputBiasVector")
        guard let output = matrix.outputImage else {
            return nil
        }
        let extent = CGRect(x: 0, y: 0, width: worldSize, height: worldSize)
        return onionCIContext.createCGImage(output, from: extent)
    }
}
