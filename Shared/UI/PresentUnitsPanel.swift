import SwiftUI

/// Android present-units rail — current frame thumbs, tap to select, drag to set arrange.
struct PresentUnitsPanel: View {
    static let width: CGFloat = 126
    static let header = Color(red: 0, green: 0xbd / 255, blue: 0x78 / 255)
    static let thumbSize: CGFloat = 60

    var frameNumber: Int
    var units: [StickmanUnit]
    var selectedName: String?
    var assets: UnitAssets
    var onSelect: (String) -> Void
    var onMove: (IndexSet, Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Frame \(frameNumber)")
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(5)
                .padding(.bottom, 5)
                .background(Self.header)

            List {
                ForEach(ordered, id: \.name) { unit in
                    row(unit)
                        .contentShape(Rectangle())
                        .highPriorityGesture(TapGesture().onEnded { onSelect(unit.name) })
                        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 4))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: onMove)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Self.header)
    }

    /// Front-most first (highest arrange), matching Android reverse arrange order.
    var ordered: [StickmanUnit] {
        units.sorted {
            if $0.arrange != $1.arrange { return $0.arrange > $1.arrange }
            return $0.name < $1.name
        }
    }

    private func row(_ unit: StickmanUnit) -> some View {
        let selected = unit.name == selectedName
        let number = UnitName.number(unit.name)
        return ZStack(alignment: .bottomTrailing) {
            Color.white
            Image(decorative: thumb(unit), scale: 1)
                .resizable()
                .scaledToFit()
                .padding(2)
            if number > 0 {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(white: 0.75))
                    .padding(3)
            }
        }
        .frame(width: Self.thumbSize, height: Self.thumbSize)
        .overlay {
            if selected {
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 3)
            }
        }
        .accessibilityLabel(unit.name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func thumb(_ unit: StickmanUnit) -> CGImage {
        let stored = assets.archive(for: unit.name)
        return ItemLoader.thumb(from: stored.zip, name: unit.name)
    }
}
