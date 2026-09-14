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
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit scene")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Menu {
                    ForEach(sizes) { size in
                        Button(size.dropdownTitle) {
                            selected = size
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scene size")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.7))
                        Text(selected.name)
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }

                Button(action: onAddCustom) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add size")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(SceneSizes.speedLabel(Int(interframes.rounded())))
                    .foregroundStyle(noInterpolation ? Color.white.opacity(0.35) : .white)
                Slider(value: $interframes, in: 0...48, step: 1)
                    .disabled(noInterpolation)
            }

            Button {
                noInterpolation.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: noInterpolation ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0x72 / 255, green: 0xbd / 255, blue: 0))
                    Text("No interpolation: \(SceneSizes.noInterpPeriodMs(tick: Int(noInterpTick.rounded())))ms between frames")
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Slider(value: $noInterpTick, in: 0...9, step: 1)
                .disabled(!noInterpolation)

            Button("Apply") {
                var next = draft
                next.width = selected.width
                next.height = selected.height
                next.interframes = Int(interframes.rounded())
                next.noInterpolation = noInterpolation
                next.noInterpolationFrames = SceneSizes.storedNoInterpFrames(tick: Int(noInterpTick.rounded()))
                onApply(next)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0x85 / 255, green: 0xb8 / 255, blue: 0x39 / 255))
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.15))
        .presentationBackground(Color(white: 0.15))
    }
}

struct CustomSceneSizeSheet: View {
    var onApply: (SceneSize) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var widthText = ""
    @State private var heightText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scene size")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            HStack {
                TextField("Width", text: $widthText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Text("×")
                    .foregroundStyle(.white)
                TextField("Height", text: $heightText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }

            Button("Apply") {
                guard let w = Int(widthText), let h = Int(heightText) else { return }
                if !SceneSizes.isValidCustom(w) || !SceneSizes.isValidCustom(h) {
                    return
                }
                onApply(SceneSize(name: "\(w) x \(h)", width: CGFloat(w), height: CGFloat(h)))
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0x85 / 255, green: 0xb8 / 255, blue: 0x39 / 255))
            .frame(maxWidth: .infinity)
            .disabled(!canApply)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.15))
        .presentationBackground(Color(white: 0.15))
    }

    private var canApply: Bool {
        guard let w = Int(widthText), let h = Int(heightText) else { return false }
        return SceneSizes.isValidCustom(w) && SceneSizes.isValidCustom(h)
    }
}
