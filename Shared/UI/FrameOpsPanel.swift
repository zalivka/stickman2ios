import SwiftUI

/// Android `FrameOpsFragment` — Add, Delete, Copy, Paste. No Paste Scene.
struct FrameOpsPanel: View {
    static let width: CGFloat = 86
    static let pane = Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255)
    static let accent = Color(red: 0x84 / 255, green: 0xd8 / 255, blue: 1)

    var canDelete: Bool
    var canPaste: Bool
    var onAdd: () -> Void
    var onDelete: () -> Void
    var onCopy: () -> Void
    var onPaste: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Self.accent
                .frame(width: 2)
            ScrollView {
                VStack(spacing: 4 / 1.5) {
                    action("Add", icon: "frame_ops_add", action: onAdd)
                    action("Delete", icon: "frame_ops_del", enabled: canDelete, action: onDelete)
                    action("Copy", icon: "frame_ops_copy", action: onCopy)
                    action("Paste", icon: "frame_ops_paste", enabled: canPaste, action: onPaste)
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.pane)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
    }

    private func action(
        _ label: String,
        icon: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8 / 1.5) {
                Image(decorative: Self.icon(icon), scale: 2)
                    .frame(width: 60, height: 60)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.87))
                    .padding(.top, 2 / 1.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16 / 1.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private static func icon(_ name: String) -> CGImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        else {
            fatalError("FrameOpsPanel missing chrome/\(name).png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "chrome/\(name).png")
        } catch {
            fatalError("FrameOpsPanel could not read \(url.path): \(error)")
        }
    }
}
