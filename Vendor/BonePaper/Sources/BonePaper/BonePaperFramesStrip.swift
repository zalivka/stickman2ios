import SwiftUI
import UIKit

struct BonePaperFramesStrip: View {
    static let width: CGFloat = 68
    private static let cellSide: CGFloat = 54
    private static let cornerRadius: CGFloat = 6

    @ObservedObject var session: BonePaperFramesSession
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var onSelect: (Int) -> Void
    var onAddEmpty: () -> Void
    var onCopy: (Int) -> Void
    var onDelete: (Int) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(session.frames) { frame in
                    frameCell(frame)
                }
                addButton
            }
            .padding(.top, topInset + 8)
            .padding(.bottom, bottomInset + 8)
            .frame(maxWidth: .infinity)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.35).ignoresSafeArea())
        .accessibilityIdentifier("bone paper frames")
    }

    private func frameCell(_ frame: BonePaperFrameSnapshot) -> some View {
        let isSelected = frame.state == session.selectedState
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color(white: 0.85))
                .frame(width: Self.cellSide, height: Self.cellSide)

            if let thumb = frame.thumbnail {
                Image(decorative: thumb, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .frame(width: Self.cellSide, height: Self.cellSide)
            }

            Text("\(frame.state + 1)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .padding(3)
        }
        .frame(width: Self.cellSide, height: Self.cellSide)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(
                    isSelected ? BonePaperChrome.selected : Color(white: 0.25),
                    lineWidth: isSelected ? 3 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .onTapGesture {
            onSelect(frame.state)
        }
        .contextMenu {
            Button {
                onCopy(frame.state)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if session.frames.count > 1 {
                Button(role: .destructive) {
                    onDelete(frame.state)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel("Frame \(frame.state + 1)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private var addButton: some View {
        Button(action: onAddEmpty) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.cellSide, height: Self.cellSide)
                .background(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.65), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add frame")
    }
}
