import SwiftUI
import UIKit

/// App settings. Chrome matches `EditPointDialog` (`doc/good_dialog.md`).
struct AppSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var antialiasing: Bool
    @State private var brushOffset: Double
    @State private var showOnionSkeleton: Bool
    @State private var skeletonColorRGB: Int
    @State private var showingSkeletonColorPicker = false
    #if DEBUG
    @State private var ignoreBmSample: Bool
    #endif
    /// When set, a DEBUG-only Tutorial button discards the current scene and
    /// replays the intro. Nil (e.g. item editor) hides the button entirely.
    let onTutorial: (() -> Void)?

    init(onTutorial: (() -> Void)? = nil) {
        _antialiasing = State(initialValue: AppSettings.paperDrawAntialiasing)
        _brushOffset = State(initialValue: Double(AppSettings.brushOffset))
        _showOnionSkeleton = State(initialValue: AppSettings.showOnionSkeleton)
        _skeletonColorRGB = State(initialValue: AppSettings.skeletonColorRGB)
        #if DEBUG
        _ignoreBmSample = State(initialValue: AppSettings.ignoreBmSample)
        #endif
        self.onTutorial = onTutorial
    }

    var body: some View {
        VStack(spacing: 0) {
            topPanel
            formBody
        }
        .background(SkeletonChrome.pane.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SkeletonChrome.pane)
    }

    private var topPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                backButton
                VStack(alignment: .leading, spacing: 1) {
                    Text("App settings")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(Self.buildCaption)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                applyButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
            SkeletonChrome.bonesAccent.frame(height: 3)
        }
        .background(SkeletonChrome.pane)
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var applyButton: some View {
        Button {
            AppSettings.paperDrawAntialiasing = antialiasing
            AppSettings.brushOffset = Int(brushOffset.rounded())
            AppSettings.showOnionSkeleton = showOnionSkeleton
            AppSettings.skeletonColorRGB = skeletonColorRGB
            #if DEBUG
            AppSettings.ignoreBmSample = ignoreBmSample
            #endif
            dismiss()
        } label: {
            Text("Apply")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .frame(minWidth: 72)
                .padding(.vertical, 8)
                .background(Self.applyGreen)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply")
    }

    private var formBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                #if DEBUG
                Text("Debug")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SkeletonChrome.toolLabel)
                    .textCase(.uppercase)
                ignoreBmSampleCard
                if onTutorial != nil {
                    tutorialCard
                }
                #endif
                Text("Editor")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SkeletonChrome.toolLabel)
                    .textCase(.uppercase)
                onionSkeletonCard
                skeletonColorCard
                Text("Paper draw")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SkeletonChrome.toolLabel)
                    .textCase(.uppercase)
                antialiasingCard
                Text("Drawing tools")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SkeletonChrome.toolLabel)
                    .textCase(.uppercase)
                brushOffsetCard
                privacyCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }

    private var onionSkeletonCard: some View {
        Button {
            showOnionSkeleton.toggle()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(Color(red: 0xCC / 255, green: 0xCC / 255, blue: 0xCC / 255))
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Onion skeleton")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Show gray skeleton of previous frame")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                Image(systemName: showOnionSkeleton ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(showOnionSkeleton ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Onion skeleton")
        .accessibilityAddTraits(showOnionSkeleton ? [.isSelected] : [])
    }

    private var skeletonColorCard: some View {
        let isCustom = skeletonColorRGB != AppSettings.defaultSkeletonColorRGB
        return HStack(alignment: .center, spacing: 12) {
            Button {
                showingSkeletonColorPicker = true
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Circle()
                        .fill(AppSettings.color(fromRGB: skeletonColorRGB))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Color of skeletons")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(AppSettings.hexString(fromRGB: skeletonColorRGB))
                            .font(.system(size: 13).monospaced())
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Color of skeletons")

            if isCustom {
                Button {
                    skeletonColorRGB = AppSettings.defaultSkeletonColorRGB
                } label: {
                    Text("Reset")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset skeleton color")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCustom ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
        )
        .sheet(isPresented: $showingSkeletonColorPicker) {
            FlexColorPickerSheet(initial: AppSettings.uiColor(fromRGB: skeletonColorRGB)) { picked in
                if let rgb = AppSettings.rgb(from: picked) {
                    skeletonColorRGB = rgb
                }
                showingSkeletonColorPicker = false
            }
        }
    }

    private var antialiasingCard: some View {
        Button {
            antialiasing.toggle()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(Color(red: 0x99 / 255, green: 0x99 / 255, blue: 0x99 / 255))
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Antialiasing")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Smooth brush and eraser edges")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                Image(systemName: antialiasing ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(antialiasing ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Antialiasing")
        .accessibilityAddTraits(antialiasing ? [.isSelected] : [])
    }

    private var brushOffsetCard: some View {
        let currentOffset = AppSettings.clampBrushOffset(Int(brushOffset.rounded()))
        let isActive = currentOffset > 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(isActive ? SkeletonChrome.bonesAccent : Color(red: 0x99 / 255, green: 0x99 / 255, blue: 0x99 / 255))
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Brush offset")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Shift drawing point above finger")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                Text("\(currentOffset) / \(AppSettings.maxBrushOffset)")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Slider(
                value: $brushOffset,
                in: 0...Double(AppSettings.maxBrushOffset),
                step: Double(AppSettings.brushOffsetStep)
            )
            .tint(SkeletonChrome.bonesAccent)
            .accessibilityLabel("Brush offset")
            .accessibilityValue("\(currentOffset) points")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
        )
    }

    private var privacyCard: some View {
        Button {
            UIApplication.shared.open(Self.privacyPolicyURL)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(Color(red: 0x99 / 255, green: 0x99 / 255, blue: 0x99 / 255))
                    .frame(width: 18, height: 18)
                Text("Privacy Policy")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Privacy Policy")
    }

    #if DEBUG
    private var ignoreBmSampleCard: some View {
        Button {
            ignoreBmSample.toggle()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ignore bm sample")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Draw the main picture and skip the 2× sidecar, like an old app")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                Image(systemName: ignoreBmSample ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ignoreBmSample ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ignore bm sample")
        .accessibilityAddTraits(ignoreBmSample ? [.isSelected] : [])
    }

    /// DEBUG only: discards the current scene and replays the intro tutorial.
    /// Visible only when the presenter supplies `onTutorial` (scene editor).
    private var tutorialCard: some View {
        Button {
            AppSettings.paperDrawAntialiasing = antialiasing
            AppSettings.brushOffset = Int(brushOffset.rounded())
            AppSettings.showOnionSkeleton = showOnionSkeleton
            AppSettings.skeletonColorRGB = skeletonColorRGB
            AppSettings.ignoreBmSample = ignoreBmSample
            onTutorial?()
            dismiss()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tutorial")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Discard current scene and replay the intro")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                Image(systemName: "play.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tutorial")
    }
    #endif

    /// `1.0 (5) · DEBUG`. Missing plist versions are a broken install.
    private static let buildCaption: String = {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !name.isEmpty
        else {
            fatalError("AppSettingsSheet missing CFBundleShortVersionString")
        }
        let code = XMLWrite.versionCode()
        #if DEBUG
        let mode = "DEBUG"
        #else
        let mode = "RELEASE"
        #endif
        return "\(name) (\(code)) · \(mode)"
    }()

    private static let privacyPolicyURL = URL(string: "https://dc2.app/privacy.html")!

    private static let applyGreen = Color(red: 0x99 / 255, green: 0xc9 / 255, blue: 0x3c / 255)
}
