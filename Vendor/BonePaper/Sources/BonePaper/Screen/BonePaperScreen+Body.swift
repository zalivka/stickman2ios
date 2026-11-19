import SwiftUI
import UIKit

extension BonePaperScreen {
    public var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let topClearance: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 0 : safe.top
            let isStripVisible = supportsFramesStrip && showFramesPanel
            let stripWidth: CGFloat = isStripVisible ? BonePaperFramesStrip.width(rearranging: isRearrangingFrames) : 0
            let backExtraLeading: CGFloat = showingMenu ? BonePaperSideMenu.width : stripWidth
            let isModalSession = hasImagePlacement || hasCanvasTransform
            var fit = BonePaperChrome.fitInsets(safe: safe, topClearance: topClearance)
            let _ = { fit.left += stripWidth }()
            ZStack {
                Color(white: 0.78).ignoresSafeArea()
                    .opacity(chromeOpacity)
                HStack(spacing: 0) {
                    BonePaperChrome.pane
                        .frame(width: safe.leading + BonePaperChrome.leftRail)
                        .frame(maxHeight: .infinity)
                        .opacity(chromeOpacity)
                    BonePaperCanvas(
                        document: document,
                        tool: tool,
                        color: UIColor(color),
                        brushSize: tool == .eraser ? eraserSize : brushSize,
                        opacity: opacity,
                        boneStart: activeBoneStart,
                        boneTip: activeBoneTip,
                        onion: activeOnion,
                        paper: paper,
                        placement: placement,
                        stage: stage,
                        zoom: $zoom,
                        fitInsets: fit,
                        onCommitStroke: recordCommittedStroke,
                        onImagePlacementChanged: { placing in
                            hasImagePlacement = placing
                        },
                        onCanvasTransformChanged: { transforming in
                            hasCanvasTransform = transforming
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea()
                .overlay(alignment: .leading) {
                    if isStripVisible {
                        BonePaperFramesStrip(
                            session: framesSession,
                            isRearranging: $isRearrangingFrames,
                            topInset: topClearance,
                            bottomInset: safe.bottom,
                            onSelect: { targetState in
                                activeStrokeSetting = nil
                                activeSwatchTrack = nil
                                drawingConfig = framesSession.selectFrame(
                                    targetState,
                                    into: document,
                                    currentConfig: drawingConfig
                                )
                            },
                            onAddEmpty: {
                                activeStrokeSetting = nil
                                activeSwatchTrack = nil
                                drawingConfig = framesSession.createEmptyFrame(
                                    afterSyncing: document,
                                    currentConfig: drawingConfig
                                )
                            },
                            onCopy: { sourceState in
                                activeStrokeSetting = nil
                                activeSwatchTrack = nil
                                drawingConfig = framesSession.copyFrame(
                                    state: sourceState,
                                    afterSyncing: document,
                                    currentConfig: drawingConfig
                                )
                            },
                            onDelete: { targetState in
                                activeStrokeSetting = nil
                                activeSwatchTrack = nil
                                drawingConfig = framesSession.deleteFrame(
                                    state: targetState,
                                    into: document,
                                    currentConfig: drawingConfig
                                )
                            },
                            onMove: { fromIndex, toIndex in
                                activeStrokeSetting = nil
                                activeSwatchTrack = nil
                                framesSession.moveFrame(
                                    from: fromIndex,
                                    to: toIndex,
                                    syncing: document,
                                    currentConfig: drawingConfig
                                )
                            }
                        )
                        .ignoresSafeArea(edges: .bottom)
                        .padding(.leading, BonePaperChrome.leftRail)
                        .opacity(chromeOpacity * (isModalSession ? 0.25 : 1.0))
                        .disabled(isModalSession)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
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
                                if !tool.isFillMode && !tool.isStrokeMode {
                                    tool = strokeMode
                                }
                            },
                            onPickTransparent: {
                                fillMode = .bucket
                                tool = .bucket
                            },
                            onSeekingBrightness: { dragging in
                                if !tool.isFillMode && !tool.isStrokeMode {
                                    tool = strokeMode
                                }
                                if dragging {
                                    activeStrokeSetting = nil
                                    previewHideWorkItem?.cancel()
                                    showingStrokePreview = true
                                } else {
                                    flashStrokePreview()
                                }
                            },
                            onFlashPreview: {
                                if !tool.isFillMode && !tool.isStrokeMode {
                                    tool = strokeMode
                                }
                                flashStrokePreview()
                            }
                        )
                        .opacity(isModalSession ? 0.25 : 1.0)
                        .disabled(isModalSession)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.trailing, BonePaperChrome.pad)
                    .padding(.top, topClearance + BonePaperChrome.pad)
                    .opacity(chromeOpacity)
                }
                .overlay(alignment: .leading) {
                    if showingMenu {
                        ZStack(alignment: .leading) {
                            Color.black.opacity(0.35)
                                .ignoresSafeArea()
                                .padding(.leading, BonePaperChrome.leftRail)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showingMenu = false
                                    }
                                }
                            BonePaperSideMenu(
                                showsFramesToggle: supportsFramesStrip,
                                showFrames: showFramesPanel,
                                hasMask: document.hasMask,
                                brushOffset: $brushOffset,
                                onPickImage: Self.imagePickerSheetProvider != nil ? {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showingMenu = false
                                    }
                                    guard !document.filling else { return }
                                    showingImagePicker = true
                                } : nil,
                                onStartTransform: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showingMenu = false
                                    }
                                    startCanvasTransform()
                                },
                                onToggleShowFrames: {
                                    withAnimation(.easeInOut(duration: 0.17)) {
                                        showFramesPanel.toggle()
                                        if !showFramesPanel {
                                            isRearrangingFrames = false
                                        }
                                        showingMenu = false
                                    }
                                },
                                onMask: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showingMenu = false
                                    }
                                    if document.hasMask {
                                        document.clearMask()
                                    } else {
                                        if document.convertDrawingToMask() {
                                            if supportsFramesStrip {
                                                framesSession.refreshActiveThumbnail(from: document.preview)
                                            }
                                        } else {
                                            BonePaperHexToast.showMessage("Draw a shape first")
                                        }
                                    }
                                }
                            )
                            .padding(.top, topClearance)
                            .padding(.leading, BonePaperChrome.leftRail)
                            .transition(.move(edge: .leading))
                        }
                        .opacity(chromeOpacity)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    BonePaperStrokeControls(
                        tool: $tool,
                        strokeMode: $strokeMode,
                        fillMode: $fillMode,
                        brushSize: $brushSize,
                        eraserSize: $eraserSize,
                        opacity: $opacity,
                        activeSetting: $activeStrokeSetting,
                        brushMarks: drawingConfig.brushSizes,
                        opacityMarks: drawingConfig.opacities,
                        eraserMarks: drawingConfig.eraserSizes,
                        showingMenu: showingMenu,
                        onToggleMenu: {
                            activeStrokeSetting = nil
                            activeSwatchTrack = nil
                            if !showingMenu {
                                brushOffset = Double(BonePaperToolStore.brushOffset)
                            }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingMenu.toggle()
                            }
                        },
                        isPlacingImage: isModalSession,
                        onCancelPlacement: {
                            if hasImagePlacement {
                                cancelImagePlacement()
                            } else if hasCanvasTransform {
                                cancelCanvasTransform()
                            }
                        },
                        canUndo: document.canUndo,
                        onUndo: {
                            document.undo()
                            if supportsFramesStrip {
                                framesSession.refreshActiveThumbnail(from: document.preview)
                            }
                        },
                        canRedo: document.canRedo,
                        onRedo: {
                            document.redo()
                            if supportsFramesStrip {
                                framesSession.refreshActiveThumbnail(from: document.preview)
                            }
                        },
                        color: color,
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
                        },
                        bottomInset: safe.bottom
                    )
                    .padding(.top, topClearance)
                    .ignoresSafeArea(edges: .bottom)
                    .opacity(chromeOpacity)
                }
                .overlay(alignment: .topLeading) {
                    BonePaperBackButton(
                        extraLeading: backExtraLeading,
                        onBack: {
                            if showingMenu {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingMenu = false
                                }
                            } else if hasImagePlacement {
                                cancelImagePlacement()
                            } else if hasCanvasTransform {
                                cancelCanvasTransform()
                            } else {
                                leave()
                            }
                        }
                    )
                    .padding(.top, topClearance)
                    .opacity(chromeOpacity)
                    .animation(.easeInOut(duration: 0.17), value: backExtraLeading)
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
                .overlay {
                    if errorStripeOpacity > 0 {
                        VStack(spacing: 0) {
                            Color.red.frame(height: 10)
                            Spacer(minLength: 0)
                            Color.red.frame(height: 10)
                        }
                        .ignoresSafeArea()
                        .opacity(errorStripeOpacity)
                        .allowsHitTesting(false)
                    }
                }
            }
            .allowsHitTesting(!leaving)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: document.fillRejectedCount) { _, _ in
            flashErrorStripes()
        }
        .task(id: document.filling) {
            guard document.filling else {
                showFillWait = false
                if supportsFramesStrip {
                    framesSession.refreshActiveThumbnail(from: document.preview)
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, document.filling else { return }
            showFillWait = true
        }
        .onAppear {
            BonePaperFlags.brushOffset = CGFloat(BonePaperToolStore.brushOffset)
            brushOffset = Double(BonePaperToolStore.brushOffset)
            if placement != nil {
                withAnimation(.easeInOut(duration: BonePaperStageView.transitionDuration)) {
                    chromeOpacity = 1
                }
            }
        }
        .onChange(of: brushOffset) { _, next in
            BonePaperToolStore.brushOffset = Int(next.rounded())
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
                if tool != .bucket && tool != .eraser {
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
        .sheet(isPresented: $showingImagePicker) {
            if let provider = Self.imagePickerSheetProvider {
                provider(
                    { pickedImage in
                        showingImagePicker = false
                        startImagePlacement(pickedImage)
                    },
                    {
                        showingImagePicker = false
                    }
                )
            }
        }
    }
}
