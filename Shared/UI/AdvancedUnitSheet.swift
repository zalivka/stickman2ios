import SwiftUI

/// Android `dialog_unit_advanced` — unit number only.
struct AdvancedUnitSheet: View {
    var currentNumber: Int
    var onApply: (Int) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var number: Int

    init(currentNumber: Int, onApply: @escaping (Int) -> Bool) {
        if currentNumber < 0 || currentNumber > 9 {
            fatalError("AdvancedUnitSheet number \(currentNumber) out of 0...9")
        }
        self.currentNumber = currentNumber
        self.onApply = onApply
        _number = State(initialValue: currentNumber)
    }

    var body: some View {
        VStack(spacing: 0) {
            topPanel
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("One frame might contain several similar items and each of them has a number. The number of the selected item is \(currentNumber)")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    sectionTitle("Number")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(0..<10, id: \.self) { value in
                            numberCard(value)
                        }
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
                Text("Advanced settings")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    if onApply(number) {
                        dismiss()
                    }
                } label: {
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(SkeletonChrome.toolLabel)
            .textCase(.uppercase)
    }

    private func numberCard(_ value: Int) -> some View {
        let selected = number == value
        return Button {
            number = value
        } label: {
            HStack(spacing: 6) {
                Text("\(value)")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.vertical, 14)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 10,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
                .fill(selected ? SkeletonChrome.boneNew : Color.clear)
                .frame(width: 4)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
