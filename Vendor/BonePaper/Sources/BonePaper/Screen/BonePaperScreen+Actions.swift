import SwiftUI
import UIKit

extension BonePaperScreen {
    func startImagePlacement(_ image: CGImage) {
        if document.filling { return }
        showingMenu = false
        activeStrokeSetting = nil
        activeSwatchTrack = nil
        previewHideWorkItem?.cancel()
        showingStrokePreview = false
        isRearrangingFrames = false
        stage.startImagePlacement(image)
        hasImagePlacement = stage.hasImagePlacement
    }

    func cancelImagePlacement() {
        stage.cancelImagePlacement()
        hasImagePlacement = false
    }

    func startCanvasTransform() {
        if document.filling { return }
        showingMenu = false
        activeStrokeSetting = nil
        activeSwatchTrack = nil
        previewHideWorkItem?.cancel()
        showingStrokePreview = false
        isRearrangingFrames = false
        if stage.startCanvasTransform() {
            hasCanvasTransform = stage.hasCanvasTransform
        } else {
            BonePaperHexToast.showMessage("Draw something first")
        }
    }

    func cancelCanvasTransform() {
        stage.cancelCanvasTransform()
        hasCanvasTransform = false
    }

    func flashErrorStripes() {
        errorStripeTask?.cancel()
        errorStripeOpacity = 0
        errorStripeTask = Task { @MainActor in
            let keyframes: [(Double, UInt64)] = [
                (1.0, 100),
                (1.0, 100),
                (0.0, 100),
                (1.0, 100),
                (1.0, 100),
                (0.0, 100)
            ]
            for (target, durationMs) in keyframes {
                if Task.isCancelled { return }
                withAnimation(.linear(duration: Double(durationMs) / 1000)) {
                    errorStripeOpacity = target
                }
                try? await Task.sleep(for: .milliseconds(durationMs))
            }
            if !Task.isCancelled {
                errorStripeOpacity = 0
            }
        }
    }

    func flashStrokePreview() {
        previewHideWorkItem?.cancel()
        showingStrokePreview = true
        let work = DispatchWorkItem {
            showingStrokePreview = false
        }
        previewHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func recordCommittedStroke() {
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
        case .pen, .line:
            guard activeUIColor.cgColor.alpha > 0 else { return }
            let hex = BonePaperColorStore.hex(from: paletteUIColor)
            drawingConfig.recordPenOrFill(colorHex: hex, brushSize: brushSize, opacity: opacity)
            drawingConfig.recordColorBrightness(baseColor: paletteUIColor, activeColor: activeUIColor)
        case .bucket, .brushfill, .rectangle, .circle:
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
        if supportsFramesStrip, tool != .bucket {
            framesSession.refreshActiveThumbnail(from: document.preview)
        }
    }

    func apply() {
        if hasImagePlacement {
            if document.filling { return }
            if stage.commitImagePlacement() {
                if supportsFramesStrip {
                    framesSession.refreshActiveThumbnail(from: document.preview)
                }
            }
            hasImagePlacement = stage.hasImagePlacement
            return
        }
        if hasCanvasTransform {
            if document.filling { return }
            if stage.commitCanvasTransform() {
                if supportsFramesStrip {
                    framesSession.refreshActiveThumbnail(from: document.preview)
                }
            }
            hasCanvasTransform = stage.hasCanvasTransform
            return
        }
        if let onApplyFrames {
            let exportedFrames = framesSession.exportAll(syncing: document, currentConfig: drawingConfig)
            #if DEBUG
            if let current = exportedFrames.first(where: { $0.state == framesSession.selectedState }) ?? exportedFrames.first {
                document.saveRecording(
                    result: current.export.image,
                    onion: onion,
                    paper: paper,
                    boneStart: activeBoneStart,
                    boneTip: activeBoneTip
                )
            }
            #endif
            onApplyFrames(exportedFrames, framesSession.selectedState)
            leave()
            return
        }
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
            boneStart: activeBoneStart,
            boneTip: activeBoneTip
        )
        #endif
        onApply(export)
        leave()
    }

    func leave() {
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
