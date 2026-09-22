import SwiftUI

/// Android present-units rail — current frame thumbs, tap to select, drag to set arrange.
struct PresentUnitsPanel: View {
    static let width: CGFloat = 126
    static let pane = Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255)
    static let accent = Color(red: 0, green: 0xbd / 255, blue: 0x78 / 255)
    static let thumbSize: CGFloat = 60

    var units: [StickmanUnit]
    var selectedName: String?
    var assets: UnitAssets
    var onSelect: (String) -> Void
    var onMove: (IndexSet, Int) -> Void
    var canPaste: Bool
    var onPaste: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Self.accent
                .frame(width: 2)
            VStack(spacing: 0) {
                Color.clear.frame(height: Self.listTop)
                List {
                    pasteRow
                        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    ForEach(ordered, id: \.name) { unit in
                        row(unit)
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded { onSelect(unit.name) })
                            .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 4))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove(perform: onMove)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.pane)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            BackCircleButton(action: onClose)
                .padding(.leading, 8)
                .padding(.top, 8)
        }
    }

    /// Clears the pinned Back control. 8 top inset + 44 circle + 8 gap.
    private static let listTop: CGFloat = 60

    /// Front-most first (highest arrange), matching Android reverse arrange order.
    var ordered: [StickmanUnit] {
        units.sorted {
            if $0.arrange != $1.arrange { return $0.arrange > $1.arrange }
            return $0.name < $1.name
        }
    }

    private var pasteRow: some View {
        Button(action: onPaste) {
            VStack(spacing: 2) {
                Image(decorative: Self.pasteIcon, scale: 2)
                    .frame(width: 45, height: 45)
                Text("Paste")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.87))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canPaste)
        .opacity(canPaste ? 1 : 0.2)
        .accessibilityLabel("Paste unit")
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

    private static let pasteIcon: CGImage = {
        guard let url = Bundle.main.url(forResource: "props_paste", withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: "props_paste", withExtension: "png")
        else {
            fatalError("PresentUnitsPanel missing chrome/props_paste.png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "chrome/props_paste.png")
        } catch {
            fatalError("PresentUnitsPanel could not read \(url.path): \(error)")
        }
    }()

    private func thumb(_ unit: StickmanUnit) -> CGImage {
        let stored = assets.archive(for: unit.name)
        return ItemLoader.thumb(from: stored.zip, name: unit.name)
    }
}
