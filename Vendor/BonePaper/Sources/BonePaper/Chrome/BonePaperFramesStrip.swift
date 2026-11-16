import SwiftUI
import UIKit

struct BonePaperFramesStrip: View {
    static let compactWidth: CGFloat = 68
    static let expandedWidth: CGFloat = 104
    static var width: CGFloat { compactWidth }

    private static let pane = Color(red: 0x33 / 255, green: 0x35 / 255, blue: 0x42 / 255)
    private static let handleTint = Color(white: 0.78)
    private static let cellSide: CGFloat = 54
    private static let rowSpacing: CGFloat = 8
    private static let rowPitch: CGFloat = cellSide + rowSpacing
    private static let cornerRadius: CGFloat = 6
    private static let handleWidth: CGFloat = 32
    private static let dragSpace = "bonepaper.frames.strip"

    static func width(rearranging: Bool) -> CGFloat {
        rearranging ? expandedWidth : compactWidth
    }

    @ObservedObject var session: BonePaperFramesSession
    @Binding var isRearranging: Bool
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var onSelect: (Int) -> Void
    var onAddEmpty: () -> Void
    var onCopy: (Int) -> Void
    var onDelete: (Int) -> Void
    var onMove: (Int, Int) -> Void

    @State private var draggedFrameID: UUID?
    @State private var dragStartY: CGFloat?
    @State private var dragOffsetY: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Self.rowSpacing) {
                ForEach(session.frames) { frame in
                    frameRow(frame)
                        .zIndex(draggedFrameID == frame.id ? 1 : 0)
                        .offset(y: draggedFrameID == frame.id ? dragOffsetY : 0)
                }
                addButton
            }
            .coordinateSpace(name: Self.dragSpace)
            .padding(.top, topInset + 8)
            .padding(.bottom, bottomInset + 8)
            .frame(maxWidth: .infinity)
        }
        .frame(width: Self.width(rearranging: isRearranging))
        .frame(maxHeight: .infinity)
        .background(Self.pane.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.17), value: isRearranging)
        .onChange(of: session.frames.count) { _, nextCount in
            if nextCount <= 1, isRearranging {
                isRearranging = false
            }
        }
        .accessibilityIdentifier("bone paper frames")
    }

    private func frameRow(_ frame: BonePaperFrameSnapshot) -> some View {
        HStack(spacing: 4) {
            frameCell(frame)
            if isRearranging {
                dragHandle(for: frame)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
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
                if !isRearranging {
                    Button {
                        isRearranging = true
                    } label: {
                        Label("Rearrange", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .accessibilityLabel("Frame \(frame.state + 1)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private func dragHandle(for frame: BonePaperFrameSnapshot) -> some View {
        let isDragging = draggedFrameID == frame.id
        return Image(uiImage: BonePaperChrome.chromeImage("drag").withRenderingMode(.alwaysTemplate))
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundStyle(isDragging ? BonePaperChrome.selected : Self.handleTint)
            .frame(width: Self.handleWidth, height: Self.cellSide)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.dragSpace))
                    .onChanged { value in
                        handleDragChanged(for: frame.id, locationY: value.location.y)
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.14)) {
                            draggedFrameID = nil
                            dragStartY = nil
                            dragOffsetY = 0
                        }
                    }
            )
            .accessibilityLabel("Reorder frame \(frame.state + 1)")
    }

    private func handleDragChanged(for frameID: UUID, locationY: CGFloat) {
        if draggedFrameID != frameID {
            draggedFrameID = frameID
            dragStartY = locationY
            dragOffsetY = 0
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        guard var anchorY = dragStartY,
              var currentIndex = session.frames.firstIndex(where: { $0.id == frameID }) else {
            return
        }
        var deltaY = locationY - anchorY
        let halfPitch = Self.rowPitch * 0.55

        while deltaY > halfPitch, currentIndex < session.frames.count - 1 {
            let nextIndex = currentIndex + 1
            withAnimation(.easeInOut(duration: 0.14)) {
                onMove(currentIndex, nextIndex)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            currentIndex = nextIndex
            anchorY += Self.rowPitch
            dragStartY = anchorY
            deltaY = locationY - anchorY
        }

        while deltaY < -halfPitch, currentIndex > 0 {
            let prevIndex = currentIndex - 1
            withAnimation(.easeInOut(duration: 0.14)) {
                onMove(currentIndex, prevIndex)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            currentIndex = prevIndex
            anchorY -= Self.rowPitch
            dragStartY = anchorY
            deltaY = locationY - anchorY
        }

        dragOffsetY = deltaY
    }

    private var addButton: some View {
        HStack(spacing: 4) {
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

            if isRearranging {
                Color.clear
                    .frame(width: Self.handleWidth, height: Self.cellSide)
            }
        }
    }
}
