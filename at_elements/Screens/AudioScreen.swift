import SwiftUI

/// Android `AudioActivity`: place sound clips on keyframes and mix them into the
/// movie soundtrack. Speech/TTS, lipsync and recording are not ported.
struct AudioScreen: View {
    /// Android `audio_palette_column` is 84dp wide with a 4dp accent line.
    private static let paletteWidth: CGFloat = 84
    private static let paletteAccentWidth: CGFloat = 4
    private static let paletteBackground = Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255)
    /// Android `audio_palette_add` is a 64dp image button; 1.5× smaller here.
    private static let paletteAddSide = AudioPaletteItem.side / 1.5
    private static let plusIcon = MainPanel.chromeImage("plus_icon")

    @Binding var scene: StickmanScene
    var assets: UnitAssets
    var backgrounds: BackgroundAssets

    @Environment(\.dismiss) private var dismiss
    @State private var navMode: DualNavigation.Mode = .frames
    @State private var range: ClosedRange<Int>
    @State private var showingPreview = false
    /// Android `audio_palette_column` starts `gone`.
    @State private var showingPalette = false
    @State private var previewing: SceneAudioClip?
    @State private var previewingPaletteId: String?
    @State private var editingClip: SceneAudioClip?
    @State private var rangeAction: RangeAction?
    @State private var chipMenuClip: SceneAudioClip?
    @State private var rangeDraft: ClosedRange<Int> = 0...0

    /// The range sheet either retimes a placed clip or places a palette sound.
    private enum RangeAction {
        case move(SceneAudioClip)
        case place(audioId: String)
    }
    @State private var paletteMenuId: String?
    @State private var toast = ""
    @StateObject private var undo = SceneAudioUndo()
    @StateObject private var preview = AudioPlayback()

    init(scene: Binding<StickmanScene>, assets: UnitAssets, backgrounds: BackgroundAssets) {
        if scene.wrappedValue.frames.isEmpty {
            assertionFailure("AudioScreen has no frames")
        }
        _scene = scene
        self.assets = assets
        self.backgrounds = backgrounds
        _range = State(
            initialValue: DualNavigation.defaultRange(
                current: scene.wrappedValue.currentIndex,
                frameCount: scene.wrappedValue.frames.count
            )
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                MainPanel(
                    onPlay: startPreview,
                    playEnabled: scene.frames.count >= 2 && !scene.audio.clips.isEmpty,
                    onEffects: togglePalette,
                    effectsActivated: showingPalette,
                    onUndo: performUndo,
                    undoEnabled: undo.canUndo
                )
                if showingPalette {
                    palettePanel
                }
                stage
            }
        }
        .overlay(alignment: .trailing) {
            DualNavigationChrome(
                frameCount: scene.frames.count,
                currentIndex: currentIndexBinding,
                range: $range,
                mode: $navMode,
                onNextAtEnd: {
                    do {
                        try scene.addFrame()
                    } catch {
                        bail(error)
                    }
                },
                stickStyle: stickStyle
            )
        }
        .overlay(alignment: .bottom) {
            chipsRow
                .padding(.bottom, 8)
                .paddingBottomSafeArea()
        }
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        .modifier(StatusBarClearance())
        .overlay(alignment: .topLeading) {
            FullscreenBackButton(
                extraLeading: showingPalette ? Self.paletteWidth : 0
            )
            .offsetLeadingIsland()
        }
        .overlay {
            if !toast.isEmpty {
                Text(toast)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.bottom, 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: seedLibraryIfNeeded)
        .onDisappear {
            onStopPreview()
            preview.stop()
        }
        .fullScreenCover(isPresented: $showingPreview) {
            FullscreenPreviewScreen(source: scene, assets: assets, backgrounds: backgrounds)
        }
        .sheet(item: $editingClip) { clip in
            AudioVolumeSheet(
                clip: clip,
                name: SceneAudioPalette.displayName(clip.audioId),
                onApply: { volume in applyVolume(clip, volume: volume) },
                onCancel: { editingClip = nil }
            )
        }
        .sheet(isPresented: rangeEditingBinding) {
            RangePicker(
                title: "Sound range",
                frameCount: scene.frames.count,
                initialRange: rangeDraft,
                preview: { index in
                    AnyView(
                        RangeFramePreview(
                            scene: scene,
                            index: index,
                            assets: assets,
                            backgrounds: backgrounds
                        )
                    )
                },
                onCancel: { rangeAction = nil },
                onApply: { next in
                    let action = rangeAction
                    rangeAction = nil
                    switch action {
                    case .move(let clip):
                        applyRange(clip, range: next)
                    case .place(let audioId):
                        placeOnRange(audioId, range: next)
                    case nil:
                        break
                    }
                }
            )
            .id("audio-range:\(rangeDraft.lowerBound):\(rangeDraft.upperBound)")
        }
        .confirmationDialog(
            "Sound",
            isPresented: paletteMenuBinding,
            titleVisibility: .visible
        ) {
            if let audioId = paletteMenuId {
                Button("Delete", role: .destructive) { removeFromPalette(audioId) }
                Button("Play") { togglePalettePreview(audioId) }
                Button("Add on Range") { addOnRange(audioId) }
            }
            Button("Cancel", role: .cancel) { paletteMenuId = nil }
        }
        .confirmationDialog(
            "Sound clip",
            isPresented: chipMenuBinding,
            titleVisibility: .visible
        ) {
            if let clip = chipMenuClip {
                Button("Volume") { beginVolumeEdit(clip) }
                Button("Range") { beginRangeEdit(clip) }
            }
            Button("Cancel", role: .cancel) { chipMenuClip = nil }
        }
    }

    // MARK: - Stage

    private var stage: some View {
        ZStack(alignment: .bottom) {
            SkeletonCanvas(
                unit: nil,
                frameUnits: scene.currentFrameOrNil?.units ?? [],
                assets: assets,
                backgrounds: backgrounds,
                bgName: scene.currentFrameOrNil?.bgName,
                bgMove: scene.currentFrameOrNil?.bgMove ?? .identity,
                cameraMove: scene.currentFrameOrNil?.cameraMove ?? .identity,
                sceneWidth: scene.width,
                sceneHeight: scene.height,
                currentIndex: scene.currentIndex,
                mode: .preview,
                showSkeleton: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SkeletonCanvas.pane)
    }

    /// One capsule per clip covering the current frame, max 4.
    @ViewBuilder
    private var chipsRow: some View {
        let covering = scene.audio.clipsCovering(scene: scene, frameIndex: scene.currentIndex)
        if !covering.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(covering.prefix(SceneAudio.maxClipsPerFrame).enumerated()), id: \.offset) { _, clip in
                    AudioClipChip(
                        clip: clip,
                        name: SceneAudioPalette.displayName(clip.audioId),
                        isPlaying: previewing == clip,
                        onTap: { togglePreview(clip) },
                        onEdit: { chipMenuClip = clip },
                        onDelete: { removeClip(clip) }
                    )
                }
            }
        }
    }

    // MARK: - Palette

    /// Android `togglePalettePanel`: opening refreshes the list, closing stops previews.
    private func togglePalette() {
        showingPalette.toggle()
        if !showingPalette {
            onStopPreview()
        }
    }

    /// Android `audio_palette_column`: a narrow `ContextPanelLayout` column that
    /// sits between the rail and the stage, add button on top, sounds below.
    private var palettePanel: some View {
        VStack(spacing: 0) {
            Button {
                // Android opens the sound picker here; iOS has no importer yet.
            } label: {
                Image(decorative: Self.plusIcon, scale: UIScreen.main.scale)
                    .resizable()
                    .scaledToFit()
                    .padding(9)
                    .frame(width: Self.paletteAddSide, height: Self.paletteAddSide)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add sound")
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(scene.audio.palette) { entry in
                        AudioPaletteItem(
                            entry: entry,
                            name: SceneAudioPalette.displayName(entry.audioId),
                            isPlaying: previewingPaletteId == entry.audioId,
                            onTap: { attachFromPalette(entry.audioId) },
                            onLongPress: {
                                paletteMenuId = entry.audioId
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.leading, Self.paletteAccentWidth)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(width: Self.paletteWidth)
        .frame(maxHeight: .infinity)
        .background(
            Self.paletteBackground
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(MainPanel.effects)
                        .frame(width: Self.paletteAccentWidth)
                }
        )
    }

    // MARK: - Playback

    private func startPreview() {
        if scene.frames.count < 2 {
            showToast("Add more frames first")
            return
        }
        if scene.audio.clips.isEmpty {
            showToast("Add a sound first")
            return
        }
        onStopPreview()
        showingPreview = true
    }

    private func togglePreview(_ clip: SceneAudioClip) {
        if previewing == clip {
            onStopPreview()
            return
        }
        guard let url = scene.audio.file(for: clip.audioId) else {
            showToast("Sound file missing")
            return
        }
        onStopPreview()
        previewing = clip
        preview.play(url: url, volume: clip.volume) { [self] in
            previewing = nil
        }
        // Android stops the preview at the clip duration; the player runs on
        // otherwise, so cap it the same way.
        if clip.durationMs > 0 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(clip.durationMs) * 1_000_000)
                if previewing == clip {
                    preview.stop()
                    previewing = nil
                }
            }
        }
    }

    private func togglePalettePreview(_ audioId: String) {
        if previewingPaletteId == audioId {
            onStopPreview()
            return
        }
        guard let url = scene.audio.file(for: audioId) else {
            showToast("Sound file missing")
            return
        }
        onStopPreview()
        previewingPaletteId = audioId
        preview.play(url: url) { [self] in
            previewingPaletteId = nil
        }
    }

    private func onStopPreview() {
        preview.stop()
        previewing = nil
        previewingPaletteId = nil
    }

    // MARK: - Edits

    private func attach(_ audioId: String) {
        guard let entry = scene.audio.paletteEntry(audioId) else {
            return
        }
        if scene.audio.clipsAt(frameIndex: scene.currentIndex).count >= SceneAudio.maxClipsPerFrame {
            showToast("Max \(SceneAudio.maxClipsPerFrame) sounds per frame")
            return
        }
        commitUndo()
        do {
            try scene.audio.registerClip(
                frameIndex: scene.currentIndex,
                audioId: audioId,
                durationMs: entry.durationMs,
                scene: scene
            )
        } catch {
            bail(error)
            return
        }
        clampRange()
    }

    private func addOnRange(_ audioId: String) {
        paletteMenuId = nil
        guard scene.audio.contains(audioId) else {
            return
        }
        if scene.frames.count < 2 {
            showToast("Add more frames first")
            return
        }
        let last = scene.frames.count - 1
        rangeDraft = scene.currentIndex...last
        rangeAction = .place(audioId: audioId)
    }

    /// Android `addClipOnRange`: the span duration is capped by the file length.
    private func placeOnRange(_ audioId: String, range: ClosedRange<Int>) {
        guard let entry = scene.audio.paletteEntry(audioId) else {
            return
        }
        if scene.audio.clipsAt(frameIndex: range.lowerBound).count >= SceneAudio.maxClipsPerFrame {
            showToast("Max \(SceneAudio.maxClipsPerFrame) sounds per frame")
            return
        }
        var duration = scene.audio.durationMsForRange(
            scene: scene,
            from: range.lowerBound,
            to: range.upperBound
        )
        duration = min(duration, entry.durationMs)
        if duration <= 0 {
            duration = entry.durationMs
        }
        commitUndo()
        do {
            try scene.audio.registerClip(
                frameIndex: range.lowerBound,
                audioId: audioId,
                durationMs: duration,
                scene: scene
            )
        } catch {
            bail(error)
        }
    }

    private func removeFromPalette(_ audioId: String) {
        paletteMenuId = nil
        commitUndo()
        do {
            try scene.audio.removePalette(audioId: audioId)
        } catch {
            bail(error)
        }
        if previewingPaletteId == audioId || previewing?.audioId == audioId {
            onStopPreview()
        }
    }

    private func removeClip(_ clip: SceneAudioClip) {
        if previewing == clip {
            onStopPreview()
        }
        commitUndo()
        do {
            try scene.audio.removeClip(clip)
        } catch {
            bail(error)
        }
    }

    private func applyVolume(_ clip: SceneAudioClip, volume: Float) {
        editingClip = nil
        commitUndo()
        do {
            try scene.audio.updateClipVolume(clip, volume: volume)
        } catch {
            bail(error)
        }
    }

    /// Android `showClipRangeDialog`: leaving the start keyframe is only allowed
    /// when that keyframe has room for one more clip.
    private func applyRange(_ clip: SceneAudioClip, range: ClosedRange<Int>) {
        guard let entry = scene.audio.paletteEntry(clip.audioId) else {
            return
        }
        let from = range.lowerBound
        let othersAtStart = scene.audio.clipsAt(frameIndex: from).filter { $0 != clip }.count
        if from != clip.frameIndex, othersAtStart >= SceneAudio.maxClipsPerFrame {
            showToast("Max \(SceneAudio.maxClipsPerFrame) sounds per frame")
            return
        }
        var duration = scene.audio.durationMsForRange(scene: scene, from: from, to: range.upperBound)
        duration = min(duration, entry.durationMs)
        if duration <= 0 {
            duration = entry.durationMs
        }
        commitUndo()
        do {
            try scene.audio.updateClipRange(clip, frameIndex: from, durationMs: duration)
        } catch {
            bail(error)
        }
    }
    private func performUndo() {
        onStopPreview()
        _ = undo.undo(audio: &scene.audio)
    }

    private func commitUndo() {
        undo.commit(scene.audio)
    }

    private func seedLibraryIfNeeded() {
        do {
            try AudioFiles.seedLibrary()
            try seedTestPalette()
        } catch {
            bail(error)
        }
    }

    /// Test sounds from `files/` stay in the palette so there is something to
    /// drag onto frames without the (not ported) sound importer.
    private func seedTestPalette() throws {
        for entry in try AudioFiles.testPaletteEntries() where !scene.audio.contains(entry.audioId) {
            scene.audio.addPalette(
                audioId: entry.audioId,
                durationMs: entry.durationMs,
                url: entry.url
            )
        }
    }

    /// Android `attachFromPalette`: a tap on the palette square places a clip;
    /// tapping the square that is previewing stops the preview.
    private func attachFromPalette(_ audioId: String) {
        if previewingPaletteId == audioId {
            onStopPreview()
            return
        }
        attach(audioId)
    }

    // MARK: - Helpers

    /// Android `sfxFrameTint`: color of the shortest of the (max 4) covering clips.
    private func stickStyle(_ index: Int) -> (color: Color?, scale: CGFloat) {
        let covering = scene.audio.clipsCovering(scene: scene, frameIndex: index)
        let n = min(covering.count, SceneAudio.maxClipsPerFrame)
        guard n > 0 else {
            return (nil, 1)
        }
        var shortest = covering[0]
        for clip in covering[1..<n] where clip.durationMs < shortest.durationMs {
            shortest = clip
        }
        return (SceneAudioPalette.clipColor(shortest.colorIndex), 1)
    }

    private var currentIndexBinding: Binding<Int> {
        Binding(
            get: { scene.currentIndex },
            set: { next in
                if next < 0 || next >= scene.frames.count {
                    assertionFailure("AudioScreen currentIndex \(next) out of \(scene.frames.count)")
                    return
                }
                scene.currentIndex = next
            }
        )
    }

    private var chipMenuBinding: Binding<Bool> {
        Binding(
            get: { chipMenuClip != nil },
            set: { shown in
                if !shown {
                    chipMenuClip = nil
                }
            }
        )
    }

    /// Android `showClipVolumeDialog`, seeded from the clip's current gain.
    private func beginVolumeEdit(_ clip: SceneAudioClip) {
        chipMenuClip = nil
        editingClip = clip
    }

    /// Android `showClipRangeDialog`, seeded from the clip's covering span.
    private func beginRangeEdit(_ clip: SceneAudioClip) {
        chipMenuClip = nil
        let last = scene.audio.lastCoveredFrameIndex(scene: scene, clip: clip)
        rangeDraft = min(clip.frameIndex, last)...max(clip.frameIndex, last)
        rangeAction = .move(clip)
    }

    private var rangeEditingBinding: Binding<Bool> {
        Binding(
            get: { rangeAction != nil },
            set: { shown in
                if !shown {
                    rangeAction = nil
                }
            }
        )
    }

    private var paletteMenuBinding: Binding<Bool> {
        Binding(
            get: { paletteMenuId != nil },
            set: { shown in
                if !shown {
                    paletteMenuId = nil
                }
            }
        )
    }

    private func clampRange() {
        let last = scene.frames.count - 1
        if last < 0 {
            assertionFailure("AudioScreen clampRange empty scene")
            return
        }
        let low = min(max(range.lowerBound, 0), last)
        let high = min(max(range.upperBound, 0), last)
        range = min(low, high)...max(low, high)
    }

    private func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == text {
                toast = ""
            }
        }
    }

    private func bail(_ error: Error) {
        print("AudioScreen: \(error)")
        showToast(ItemLoadError.text(error))
    }
}

/// Android `showClipVolumeDialog`.
private struct AudioVolumeSheet: View {
    let clip: SceneAudioClip
    let name: String
    var onApply: (Float) -> Void
    var onCancel: () -> Void

    @State private var percent: Double

    init(
        clip: SceneAudioClip,
        name: String,
        onApply: @escaping (Float) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.clip = clip
        self.name = name
        self.onApply = onApply
        self.onCancel = onCancel
        _percent = State(initialValue: Double(clip.volume) * 100)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Volume: \(Int(percent.rounded()))%")
                    .font(.system(size: 16, weight: .semibold))
                Slider(value: $percent, in: 0...100, step: 1)
                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { onApply(Float(percent / 100)) }
                }
            }
        }
        .presentationDetents([.height(260)])
    }
}
