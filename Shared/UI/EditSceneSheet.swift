import SwiftUI

struct EditSceneDraft {
    var width: CGFloat
    var height: CGFloat
    var interframes: Int
    var noInterpolation: Bool
    var noInterpolationFrames: Int
}

struct EditSceneSheet: View {
    let draft: EditSceneDraft
    var onAddCustom: () -> Void
    var onApply: (EditSceneDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sizes: [SceneSize]
    @State private var selected: SceneSize
    @State private var interframes: Double
    @State private var noInterpolation: Bool
    @State private var noInterpTick: Double

    init(
        draft: EditSceneDraft,
        onAddCustom: @escaping () -> Void,
        onApply: @escaping (EditSceneDraft) -> Void
    ) {
        self.draft = draft
        self.onAddCustom = onAddCustom
        self.onApply = onApply
        let available = SceneSizes.available(currentWidth: draft.width, currentHeight: draft.height)
        _sizes = State(initialValue: available)
        let match = available.first(where: { $0.width == draft.width && $0.height == draft.height })
            ?? available[available.count - 1]
        _selected = State(initialValue: match)
        _interframes = State(initialValue: Double(min(max(draft.interframes, 0), 48)))
        _noInterpolation = State(initialValue: draft.noInterpolation)
        _noInterpTick = State(initialValue: Double(SceneSizes.tick(storedNoInterpFrames: draft.noInterpolationFrames)))
    }

    var body: some View {
        VStack(spacing: 0) {
            topPanel
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("Size")
                    HStack(spacing: 8) {
                        sizeCard
                        plusCard
                    }
                    sectionTitle("Speed")
                    speedCard
                    sectionTitle("Playback")
                    noInterpCard
                    if noInterpolation {
                        noInterpSlider
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(SkeletonChrome.pane.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(SkeletonChrome.pane)
    }

    private var topPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackCircleButton(action: { dismiss() })
                Text("Edit scene")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: apply) {
                    Text("Apply")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(minWidth: 72)
                        .padding(.vertical, 8)
                        .background(SkeletonChrome.boneNew)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apply")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
            SkeletonChrome.bonesAccent.frame(height: 3)
        }
        .background(SkeletonChrome.pane)
    }

    private var sizeCard: some View {
        Menu {
            ForEach(sizes) { size in
                Button(size.dropdownTitle) {
                    selected = size
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selected.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(Int(selected.width)) × \(Int(selected.height))")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 14)
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scene size")
    }

    private var plusCard: some View {
        Button(action: onAddCustom) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add size")
    }

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(SceneSizes.speedLabel(Int(interframes.rounded())))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(noInterpolation ? Color.white.opacity(0.4) : .white)
            Slider(value: $interframes, in: 0...48, step: 1)
                .tint(SkeletonChrome.boneNew)
                .disabled(noInterpolation)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .opacity(noInterpolation ? 0.4 : 1)
    }

    private var noInterpCard: some View {
        Button {
            noInterpolation.toggle()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No interpolation")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(SceneSizes.noInterpPeriodMs(tick: Int(noInterpTick.rounded())))ms between frames")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                Image(systemName: noInterpolation ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(noInterpolation ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 10,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
                .fill(noInterpolation ? SkeletonChrome.boneNew : Color.clear)
                .frame(width: 4)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("No interpolation")
        .accessibilityAddTraits(noInterpolation ? [.isSelected] : [])
    }

    private var noInterpSlider: some View {
        Slider(value: $noInterpTick, in: 0...9, step: 1)
            .tint(SkeletonChrome.boneNew)
            .padding(.horizontal, 4)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(SkeletonChrome.toolLabel)
            .textCase(.uppercase)
    }

    private func apply() {
        var next = draft
        next.width = selected.width
        next.height = selected.height
        next.interframes = Int(interframes.rounded())
        next.noInterpolation = noInterpolation
        next.noInterpolationFrames = SceneSizes.storedNoInterpFrames(tick: Int(noInterpTick.rounded()))
        onApply(next)
        dismiss()
    }
}

struct CustomSceneSizeSheet: View {
    var onApply: (SceneSize) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var widthText = ""
    @State private var heightText = ""

    var body: some View {
        VStack(spacing: 0) {
            topPanel
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Width")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SkeletonChrome.toolLabel)
                        .textCase(.uppercase)
                    sizeField("Width", text: $widthText)
                    Text("Height")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SkeletonChrome.toolLabel)
                        .textCase(.uppercase)
                    sizeField("Height", text: $heightText)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(SkeletonChrome.pane.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(SkeletonChrome.pane)
    }

    private var topPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackCircleButton(action: { dismiss() })
                Text(canApply ? "Scene size" : "Dimensions: between \(SceneSizes.customMin) and \(SceneSizes.customMax)")
                    .font(.system(size: canApply ? 17 : 22, weight: .semibold))
                    .foregroundStyle(canApply ? .white : Color(red: 1, green: 0.45, blue: 0.7))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: apply) {
                    Text("Apply")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(minWidth: 72)
                        .padding(.vertical, 8)
                        .background(canApply ? SkeletonChrome.boneNew : Color.white.opacity(0.25))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canApply)
                .opacity(canApply ? 1 : 0.4)
                .accessibilityLabel("Apply")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
            SkeletonChrome.bonesAccent.frame(height: 3)
        }
        .background(SkeletonChrome.pane)
    }

    private func sizeField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.numberPad)
            .font(.system(size: 22))
            .foregroundStyle(.black)
            .tint(.black)
            .textFieldStyle(.plain)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var canApply: Bool {
        guard let w = Int(widthText), let h = Int(heightText) else { return false }
        return SceneSizes.isValidCustom(w) && SceneSizes.isValidCustom(h)
    }

    private func apply() {
        guard let w = Int(widthText), let h = Int(heightText),
              SceneSizes.isValidCustom(w), SceneSizes.isValidCustom(h)
        else {
            return
        }
        onApply(SceneSize(name: "\(w) x \(h)", width: CGFloat(w), height: CGFloat(h)))
        dismiss()
    }
}
