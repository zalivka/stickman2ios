import SwiftUI

/// Android `audio_sfx_chip.xml` + `audio_palette_item.xml` in one file: the
/// placed-clip capsules over the stage and the palette squares beside it.
enum SceneAudioPalette {
    /// Android `CLIP_COLORS`: cam_chip_03/07/04/09.
    static let clipColors: [Color] = [
        Color(red: 0xFF / 255, green: 0xAB / 255, blue: 0x00 / 255),
        Color(red: 0x29 / 255, green: 0x79 / 255, blue: 0xFF / 255),
        Color(red: 0x00 / 255, green: 0xC8 / 255, blue: 0x53 / 255),
        Color(red: 0xD5 / 255, green: 0x00 / 255, blue: 0xF9 / 255),
    ]

    static let chipText = Color(red: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255)
    static let chipOutline = Color.white
    static let chipOutlinePlaying = Color(red: 0xFF / 255, green: 0x17 / 255, blue: 0x44 / 255)
    static let volumeLow = Color(red: 0xFF / 255, green: 0x17 / 255, blue: 0x44 / 255)
    static let volumeMid = Color(red: 0xFF / 255, green: 0xAB / 255, blue: 0x00 / 255)
    static let volumeHigh = Color(red: 0x00 / 255, green: 0xC8 / 255, blue: 0x53 / 255)

    static func clipColor(_ index: Int) -> Color {
        guard index >= 0, index < clipColors.count else {
            return clipColors[0]
        }
        return clipColors[index]
    }

    /// Android `volumeMeterColor`: 0–29 red, 30–69 yellow, 70–100 green.
    static func volumeColor(_ volume: Float) -> Color {
        let pct = Int((SceneAudioClip.clampVolume(volume) * 100).rounded())
        if pct < 30 {
            return volumeLow
        }
        if pct < 70 {
            return volumeMid
        }
        return volumeHigh
    }

    static func displayName(_ audioId: String) -> String {
        AudioFiles.libraryEntry(audioId: audioId)?.displayName ?? audioId
    }

    /// Android `SoundEffectsRepository.colorForName`: hue from Java's
    /// `String.hashCode`, 0.55 saturation, 0.90 value.
    static func colorForName(_ name: String) -> Color {
        var hash: Int32 = 0
        for unit in name.utf16 {
            hash = hash &* 31 &+ Int32(bitPattern: UInt32(unit))
        }
        let hue = Double(UInt32(bitPattern: hash) & 0xFFFF) / 65535
        return Color(hue: hue, saturation: 0.55, brightness: 0.90)
    }
}

/// One placed clip over the current frame. Left rail = volume, pill = name.
/// Android `audio_sfx_chip`: fixed 36dp tall, 6dp rail, 68dp label, 28dp delete.
struct AudioClipChip: View {
    static let height: CGFloat = 36
    static let volumeRailWidth: CGFloat = 6
    static let labelWidth: CGFloat = 68
    static let deleteSide: CGFloat = 28

    let clip: SceneAudioClip
    let name: String
    let isPlaying: Bool
    var onTap: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Android `applyChipVolumeMeter`: spacer on top, colored fill below,
            // weights 1-volume / volume against the fixed chip height.
            VStack(spacing: 0) {
                Color.black
                Rectangle()
                    .fill(SceneAudioPalette.volumeColor(clip.volume))
                    .frame(height: Self.height * CGFloat(SceneAudioClip.clampVolume(clip.volume)))
            }
            .frame(width: Self.volumeRailWidth)
            Text(isPlaying ? String(format: "%.1fs", Double(clip.durationMs) / 1000) : name)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SceneAudioPalette.chipText)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .frame(width: Self.labelWidth, height: Self.height)
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SceneAudioPalette.chipText)
                    .frame(width: Self.deleteSide, height: Self.deleteSide)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .frame(height: Self.height)
        .background(SceneAudioPalette.clipColor(clip.colorIndex))
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: Self.height / 2,
            topTrailingRadius: Self.height / 2,
            style: .continuous
        ))
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: Self.height / 2,
                topTrailingRadius: Self.height / 2,
                style: .continuous
            )
            .stroke(isPlaying ? SceneAudioPalette.chipOutlinePlaying : SceneAudioPalette.chipOutline, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.45, perform: onEdit)
    }
}

/// Palette entry square: Android `audio_palette_item`.
struct AudioPaletteItem: View {
    /// Android `audio_palette_item` is a 64dp square, `squareBackground` 6dp radius, 2dp stroke.
    static let side: CGFloat = 64

    let entry: SceneAudioPaletteEntry
    let name: String
    let isPlaying: Bool
    var onTap: () -> Void
    var onLongPress: () -> Void

    var body: some View {
        Text(isPlaying ? String(format: "%.1fs", Double(entry.durationMs) / 1000) : name)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .padding(4)
            .frame(width: Self.side, height: Self.side)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SceneAudioPalette.colorForName(name))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isPlaying ? SceneAudioPalette.chipOutlinePlaying : SceneAudioPalette.chipOutline, lineWidth: 2)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.45, perform: onLongPress)
    }
}
