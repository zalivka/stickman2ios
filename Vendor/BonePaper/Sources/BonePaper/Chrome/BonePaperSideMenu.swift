import SwiftUI

struct BonePaperSideMenu: View {
    static let width: CGFloat = 200
    private static let dividerColor = Color(red: 0x38 / 255, green: 0x3A / 255, blue: 0x4A / 255)
    private static let summaryColor = Color(red: 0x9B / 255, green: 0xA0 / 255, blue: 0xB0 / 255)

    var showsFramesToggle: Bool
    var showFrames: Bool
    var hasMask: Bool
    @Binding var brushOffset: Double
    var onPickImage: (() -> Void)? = nil
    var onStartTransform: (() -> Void)? = nil
    var onToggleShowFrames: () -> Void
    var onMask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onPickImage {
                Button(action: onPickImage) {
                    HStack(spacing: 10) {
                        Image(uiImage: BonePaperChrome.chromeImage("v3pickimage"))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                        Text("Image")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if onStartTransform == nil {
                    Self.dividerColor
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                }
            }

            if let onStartTransform {
                Button(action: onStartTransform) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22)
                        Text("Transform")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Self.dividerColor
                    .frame(height: 1)
                    .padding(.horizontal, 12)
            }

            if showsFramesToggle {
                Button(action: onToggleShowFrames) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack")
                            .font(.system(size: 16))
                            .frame(width: 22)
                        Text("Show frames")
                            .font(.system(size: 15))
                        Spacer(minLength: 0)
                        Image(systemName: showFrames ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(showFrames ? BonePaperChrome.selected : Color(white: 0.85))
                    }
                    .foregroundStyle(Color(white: 0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if BonePaperFlags.showsMaskButton {
                Button(action: onMask) {
                    HStack(spacing: 10) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 16))
                            .frame(width: 22)
                        Text(hasMask ? "Clear mask" : "Mask")
                            .font(.system(size: 15))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(hasMask ? BonePaperChrome.selected : Color(white: 0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if showsFramesToggle || BonePaperFlags.showsMaskButton {
                Self.dividerColor
                    .frame(height: 1)
                    .padding(.horizontal, 12)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Brush offset")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Text("Some space between finger and drawing")
                    .font(.system(size: 12))
                    .foregroundStyle(Self.summaryColor)
                Slider(
                    value: $brushOffset,
                    in: 0...Double(BonePaperToolStore.maxBrushOffset),
                    step: Double(BonePaperToolStore.brushOffsetStep)
                )
                .tint(BonePaperChrome.selected)
                .padding(.top, 2)
                .accessibilityLabel("Brush offset")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Spacer(minLength: 0)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(BonePaperChrome.pane.ignoresSafeArea())
        .overlay(alignment: .leading) {
            Self.dividerColor
                .frame(width: 1)
                .ignoresSafeArea()
        }
        .accessibilityIdentifier("bone paper side menu")
    }
}
