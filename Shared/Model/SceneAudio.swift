import CoreGraphics
import Foundation

/// One placed sound: Android `AudioClipPoint`. Starts on a source keyframe and
/// covers generated time forward until `durationMs` is exhausted.
struct SceneAudioClip: Equatable, Hashable, Identifiable {
    static let defaultVolume: Float = 1

    var audioId: String
    var frameIndex: Int
    var durationMs: Int64
    /// Stable chip palette index, Android `CLIP_COLORS` 0..3.
    var colorIndex: Int
    /// Linear gain 0..1 applied at merge and preview.
    var volume: Float

    var id: String { "\(audioId)@\(frameIndex)#\(colorIndex)" }

    init(
        audioId: String,
        frameIndex: Int,
        durationMs: Int64,
        colorIndex: Int = 0,
        volume: Float = SceneAudioClip.defaultVolume
    ) {
        self.audioId = audioId
        self.frameIndex = frameIndex
        self.durationMs = durationMs
        self.colorIndex = colorIndex
        self.volume = SceneAudioClip.clampVolume(volume)
    }

    func withVolume(_ volume: Float) -> SceneAudioClip {
        SceneAudioClip(
            audioId: audioId,
            frameIndex: frameIndex,
            durationMs: durationMs,
            colorIndex: colorIndex,
            volume: volume
        )
    }

    func withPlacement(frameIndex: Int, durationMs: Int64) -> SceneAudioClip {
        SceneAudioClip(
            audioId: audioId,
            frameIndex: frameIndex,
            durationMs: durationMs,
            colorIndex: colorIndex,
            volume: volume
        )
    }

    static func clampVolume(_ volume: Float) -> Float {
        if volume.isNaN || volume < 0 {
            return 0
        }
        if volume > 1 {
            return 1
        }
        return volume
    }
}

/// Scene-scoped fast-access sound: Android `AudioPalette.Entry`, plus the file
/// itself because iOS has no shared sound library singleton.
struct SceneAudioPaletteEntry: Equatable, Identifiable {
    var audioId: String
    var durationMs: Int64
    var url: URL

    var id: String { audioId }
}

/// Speech sidecars (`audio_v1/dialogue.json`, `viseme_v1/*`) carried through
/// untouched: iOS does not play speech, but saving must not drop it.
struct SceneAudioPassThrough: Equatable {
    var name: String
    var data: Data
}

/// Per-scene audio: palette of unique sounds plus placements on keyframes.
/// Android `StageAudio` without the speech/TTS branches.
struct SceneAudio: Equatable {
    static let maxClipsPerFrame = 4
    static let colorCount = 4

    var palette: [SceneAudioPaletteEntry] = []
    var clips: [SceneAudioClip] = []
    var passThrough: [SceneAudioPassThrough] = []
    /// Android `StageAudio.mSpeechByDefault`, persisted as `SceneMetadata.speechUsed`.
    /// True only when the scene carries real speech (dialogue entries or visemes);
    /// an empty `audio_v1/dialogue.json` is a sidecar to preserve, not speech to play.
    var hasSpeech: Bool = false

    var isEmpty: Bool {
        palette.isEmpty && clips.isEmpty && passThrough.isEmpty
    }

    func paletteEntry(_ audioId: String) -> SceneAudioPaletteEntry? {
        palette.first { $0.audioId == audioId }
    }

    func contains(_ audioId: String) -> Bool {
        paletteEntry(audioId) != nil
    }

    func file(for audioId: String) -> URL? {
        paletteEntry(audioId)?.url
    }

    func clipsAt(frameIndex: Int) -> [SceneAudioClip] {
        clips.filter { $0.frameIndex == frameIndex }
    }

    func clipsCovering(scene: StickmanScene, frameIndex: Int) -> [SceneAudioClip] {
        clips.filter { SceneAudioTimeline.coversFrame(scene: scene, clip: $0, frameIndex: frameIndex) }
    }

    /// `StageAudio.lastCoveredFrameIndex`.
    func lastCoveredFrameIndex(scene: StickmanScene, clip: SceneAudioClip) -> Int {
        var last = clip.frameIndex
        for index in clip.frameIndex..<scene.frames.count {
            if SceneAudioTimeline.coversFrame(scene: scene, clip: clip, frameIndex: index) {
                last = index
            } else if index > clip.frameIndex {
                break
            }
        }
        return last
    }

    /// `StageAudio.durationMsForRange`; a single-frame range is a 0 ms clip.
    func durationMsForRange(scene: StickmanScene, from: Int, to: Int) -> Int64 {
        SceneAudioTimeline.durationMsForRange(scene: scene, from: from, to: to)
    }

    /// Adds the sound to the palette if missing. Returns true when newly added.
    @discardableResult
    mutating func addPalette(audioId: String, durationMs: Int64, url: URL) -> Bool {
        if let existing = paletteEntry(audioId) {
            if existing.url != url {
                // Same id, different file would silently play the wrong bytes.
                palette = palette.map { entry in
                    entry.audioId == audioId
                        ? SceneAudioPaletteEntry(audioId: audioId, durationMs: durationMs, url: url)
                        : entry
                }
            }
            return false
        }
        palette.append(SceneAudioPaletteEntry(audioId: audioId, durationMs: durationMs, url: url))
        return true
    }

    /// Removes the sound and every placement of it.
    mutating func removePalette(audioId: String) throws {
        guard contains(audioId) else {
            throw SceneLoadError(message: "SceneAudio palette has no '\(audioId)'")
        }
        palette.removeAll { $0.audioId == audioId }
        clips.removeAll { $0.audioId == audioId }
    }

    /// `StageAudio.registerClipPoint`: place an existing palette sound on a keyframe.
    @discardableResult
    mutating func registerClip(
        frameIndex: Int,
        audioId: String,
        durationMs: Int64,
        colorIndex: Int = -1,
        volume: Float = SceneAudioClip.defaultVolume,
        scene: StickmanScene
    ) throws -> SceneAudioClip {
        guard contains(audioId) else {
            throw SceneLoadError(message: "SceneAudio register clip '\(audioId)' not in palette")
        }
        if frameIndex < 0 || frameIndex >= scene.frames.count {
            throw SceneLoadError(message: "SceneAudio clip frame \(frameIndex) out of \(scene.frames.count)")
        }
        if durationMs <= 0 {
            throw SceneLoadError(message: "SceneAudio clip '\(audioId)' duration \(durationMs)")
        }
        let atFrame = clipsAt(frameIndex: frameIndex)
        if atFrame.count >= Self.maxClipsPerFrame {
            throw SceneLoadError(
                message: "SceneAudio max \(Self.maxClipsPerFrame) clips at frame \(frameIndex)"
            )
        }
        let resolvedColor = colorIndex >= 0 && colorIndex < Self.colorCount
            ? colorIndex
            : allocateColorIndex()
        let clip = SceneAudioClip(
            audioId: audioId,
            frameIndex: frameIndex,
            durationMs: durationMs,
            colorIndex: resolvedColor,
            volume: volume
        )
        clips.append(clip)
        return clip
    }

    /// Replaces `clip` with the same placement at a new volume.
    mutating func updateClipVolume(_ clip: SceneAudioClip, volume: Float) throws {
        guard let index = clips.firstIndex(of: clip) else {
            throw SceneLoadError(message: "SceneAudio clip '\(clip.audioId)' not placed")
        }
        clips[index] = clip.withVolume(volume)
    }

    /// Replaces `clip` with a new start keyframe and coverage duration.
    mutating func updateClipRange(_ clip: SceneAudioClip, frameIndex: Int, durationMs: Int64) throws {
        guard let index = clips.firstIndex(of: clip) else {
            throw SceneLoadError(message: "SceneAudio clip '\(clip.audioId)' not placed")
        }
        if durationMs < 0 {
            throw SceneLoadError(message: "SceneAudio clip '\(clip.audioId)' duration \(durationMs)")
        }
        clips[index] = clip.withPlacement(frameIndex: frameIndex, durationMs: durationMs)
    }

    mutating func removeClip(_ clip: SceneAudioClip) throws {
        guard let index = clips.firstIndex(of: clip) else {
            throw SceneLoadError(message: "SceneAudio clip '\(clip.audioId)' not placed")
        }
        clips.remove(at: index)
    }

    mutating func replaceClips(_ next: [SceneAudioClip]) {
        clips = next
    }

    /// Prefer an unused palette slot among existing clips; otherwise cycle.
    func allocateColorIndex() -> Int {
        var used = Array(repeating: false, count: Self.colorCount)
        for clip in clips where clip.colorIndex >= 0 && clip.colorIndex < used.count {
            used[clip.colorIndex] = true
        }
        for index in used.indices where !used[index] {
            return index
        }
        return clips.count % Self.colorCount
    }

    /// Frame insert: a clip on or after the new frame moves down one so it stays
    /// on the same keyframe. Durations stay as authored — stretching them here
    /// would silently change what the user hears.
    mutating func reconcileInsert(at index: Int, oldFrameCount: Int) {
        if oldFrameCount < 1 || index < 0 || index > oldFrameCount {
            assertionFailure("SceneAudio insert \(index) out of \(oldFrameCount)")
            return
        }
        clips = clips.map { clip in
            clip.frameIndex >= index
                ? clip.withPlacement(frameIndex: clip.frameIndex + 1, durationMs: clip.durationMs)
                : clip
        }
    }

    /// Frame delete: clips on a deleted keyframe go away, later ones shift up.
    mutating func reconcileDelete(deleted: [Int]) {
        let deletedSet = Set(deleted)
        clips = clips.compactMap { clip in
            if deletedSet.contains(clip.frameIndex) {
                return nil
            }
            let shift = deletedSet.filter { $0 < clip.frameIndex }.count
            return clip.withPlacement(frameIndex: clip.frameIndex - shift, durationMs: clip.durationMs)
        }
    }

    /// Bulk frame insert: clips on the inserted frames land on the copies, so
    /// only clips at or after the insertion point move.
    mutating func shiftClips(insertedAtOrAfter index: Int, by count: Int) {
        if count < 1 {
            assertionFailure("SceneAudio shift \(count)")
            return
        }
        clips = clips.map { clip in
            clip.frameIndex >= index
                ? clip.withPlacement(frameIndex: clip.frameIndex + count, durationMs: clip.durationMs)
                : clip
        }
    }

    /// Merge inputs for a generated movie: `StageAudio.mergeClips`.
    func timedFiles(movie: StickmanScene) throws -> [TimedAudioFile] {
        var timed: [TimedAudioFile] = []
        for clip in clips {
            guard let entry = paletteEntry(clip.audioId) else {
                throw SceneLoadError(message: "SceneAudio clip '\(clip.audioId)' has no palette entry")
            }
            let offset = SceneAudioTimeline.generatedOffsetMs(movie: movie, sourceFrameIndex: clip.frameIndex)
            let playMs = clip.durationMs == 0
                ? max(1, Int64(SceneAudioTimeline.frameMs.rounded()))
                : clip.durationMs
            timed.append(
                TimedAudioFile(
                    file: entry.url,
                    offsetMs: offset,
                    volume: clip.volume,
                    durationMs: playMs
                )
            )
        }
        return timed
    }
}

/// Android `SceneConfig.FPS` and the per-span accounted time used by
/// `StageAudio.coversFrame` / `durationMsForRange`.
enum SceneAudioTimeline {
    static let fps: Float = 60
    static let frameMs: Float = 1000 / fps

    /// Same division as `JpegVideoAssembler`: `Double(frameCount) / Double(fps)`.
    /// Kept separate from the `Float` helpers, which mirror Android's float math.
    private static let exactFrameMs: Double = 1000.0 / Double(fps)

    /// Frame index for a movie clock reading. Playback drives `currentIndex`
    /// from elapsed time, never from a tick count: `Timer` fires on the display
    /// refresh, so counting ticks stretches or squashes the movie under any
    /// refresh rate or load. Frame `index` owns `[index, index + 1) * frameMs`.
    static func index(atMs elapsedMs: Double, frameCount: Int) -> Int {
        if frameCount < 1 {
            return 0
        }
        let raw = Int(elapsedMs / exactFrameMs)
        return min(max(raw, 0), frameCount - 1)
    }

    /// Total movie duration. Matches the exported picture: `JpegVideoAssembler`
    /// writes `frameCount` frames at `fps`, so every frame owns a full `frameMs`.
    static func durationMs(frameCount: Int) -> Double {
        Double(max(frameCount, 0)) * exactFrameMs
    }

    /// Movie time of frame `index`, truncated to whole ms the way the merged
    /// soundtrack stores offsets. Used to resume audio where the picture is.
    static func storedOffsetMs(frameIndex: Int) -> Int64 {
        Int64(Float(max(frameIndex, 0)) * frameMs)
    }

    /// Untruncated movie time of frame `index`. The integer helpers round down,
    /// which would drift the playback clock by up to 1 ms per resume.
    static func exactTimeMs(frameIndex: Int) -> Double {
        Double(max(frameIndex, 0)) * exactFrameMs
    }

    /// Android `mNoInterpolation ? mNoInterpolationFramesNumber : mInterframesNumber`.
    static func generatedFramesPerSpan(scene: StickmanScene) -> Int {
        scene.noInterpolation ? scene.noInterpolationFrames : scene.interframes
    }

    /// Generated milliseconds burned by source gap `gapIndex` (the lower frame
    /// index of the gap), matching `StageAudio`'s per-span accounting.
    static func gapMs(scene: StickmanScene, gapIndex: Int) -> Int64 {
        let speeds = scene.speedModifier.fineSpeedValues(frameCount: scene.frames.count)
        let speed = gapIndex >= 0 && gapIndex < speeds.count ? speeds[gapIndex] : 1
        let genPerSpan = generatedFramesPerSpan(scene: scene)
        return Int64(Float(genPerSpan) * speed * frameMs)
    }

    /// `StageAudio.coversFrame`.
    static func coversFrame(scene: StickmanScene, clip: SceneAudioClip, frameIndex: Int) -> Bool {
        if frameIndex < clip.frameIndex {
            return false
        }
        if clip.durationMs <= 0 {
            return frameIndex == clip.frameIndex
        }
        let framesNumber = scene.frames.count
        if frameIndex >= framesNumber {
            return false
        }
        // One speed slice per call: `gapMs` re-derives it, which is O(frames)
        // and this runs for every chip and every seek-bar tick.
        let speeds = scene.speedModifier.fineSpeedValues(frameCount: framesNumber)
        let genPerSpan = generatedFramesPerSpan(scene: scene)
        var remaining = clip.durationMs
        var index = clip.frameIndex
        while index < framesNumber {
            if index == frameIndex {
                return remaining > 0
            }
            if index >= framesNumber - 1 {
                return false
            }
            remaining -= gapMs(speeds: speeds, generatedPerSpan: genPerSpan, gapIndex: index)
            if remaining <= 0 {
                return false
            }
            index += 1
        }
        return false
    }

    /// `gapMs` with the speed slice and span length already resolved.
    static func gapMs(speeds: [Float], generatedPerSpan: Int, gapIndex: Int) -> Int64 {
        let speed = gapIndex >= 0 && gapIndex < speeds.count ? speeds[gapIndex] : 1
        return Int64(Float(generatedPerSpan) * speed * frameMs)
    }

    /// `StageAudio.durationMsForRange`.
    static func durationMsForRange(scene: StickmanScene, from: Int, to: Int) -> Int64 {
        let start = min(from, to)
        let end = max(from, to)
        if start < 0 || end >= scene.frames.count {
            assertionFailure("SceneAudioTimeline range \(start)..\(end) out of \(scene.frames.count)")
            return 0
        }
        if start == end {
            return 0
        }
        var elapsed: Int64 = 0
        for index in start..<end {
            elapsed += gapMs(scene: scene, gapIndex: index)
        }
        return elapsed
    }

    /// `StageAudio.toGeneratedOffsetMs`: first generated frame whose
    /// `originFrameIndex` matches the source keyframe.
    static func generatedOffsetMs(movie: StickmanScene, sourceFrameIndex: Int) -> Int64 {
        for (index, frame) in movie.frames.enumerated() where frame.originFrameIndex == sourceFrameIndex {
            return Int64(Float(index) * frameMs)
        }
        return Int64(Float(movie.frames.count) * frameMs)
    }
}
