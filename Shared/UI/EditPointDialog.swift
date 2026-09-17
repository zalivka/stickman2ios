import SwiftUI

/// Android `EditPointDialog` — attach No/Master/Slave, Invisible, Help.
struct EditPointDialog: View {
    var isBase: Bool
    var onApply: (Attachable, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var attachable: Attachable
    @State private var fixed: Bool
    @State private var showingHelp = false

    init(isBase: Bool, attachable: Attachable, fixed: Bool, onApply: @escaping (Attachable, Bool) -> Void) {
        self.isBase = isBase
        self.onApply = onApply
        _attachable = State(initialValue: attachable)
        _fixed = State(initialValue: isBase ? false : fixed)
    }

    var body: some View {
        VStack(spacing: 0) {
            topPanel
            if showingHelp {
                helpBody
            } else {
                formBody
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
                backButton
                Text(showingHelp ? "Help" : "Point attributes")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showingHelp {
                    Color.clear.frame(width: 72, height: 36)
                } else {
                    applyButton
                }
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
            if showingHelp {
                showingHelp = false
            } else {
                dismiss()
            }
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
            onApply(attachable, isBase ? false : fixed)
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
                sectionTitle("Attach")
                VStack(spacing: 8) {
                    attachCard(
                        .none,
                        title: "No",
                        subtitle: "Not used for attaching items",
                        color: SkeletonCanvas.boneCommon
                    )
                    attachCard(
                        .master,
                        title: "Master",
                        subtitle: "Other items can attach to this point",
                        color: SkeletonCanvas.boneMaster
                    )
                    attachCard(
                        .slave,
                        title: "Slave",
                        subtitle: isBase
                            ? "This item's root can attach to a master"
                            : "Only the base point can be Slave",
                        color: SkeletonCanvas.boneSlave,
                        enabled: isBase
                    )
                }

                sectionTitle("Node")
                invisibleCard

                Button {
                    showingHelp = true
                } label: {
                    HStack {
                        Text("Help")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }

    private var helpBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                helpRow(icon: "point_help_master", text: "\"Master\" point - another item can be attached to this point")
                helpRow(icon: "point_help_slave", text: "\"Slave\" point - the root point of an item that can be used for attaching this item to another")
                helpImage("point_help_ms1")
                helpImage("point_help_ms2")
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 1)
                Text("\"Invisible\" - a point that is not intended for dragging")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .padding(16)
            .padding(.bottom, 28)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(SkeletonChrome.toolLabel)
            .textCase(.uppercase)
    }

    private func attachCard(
        _ role: Attachable,
        title: String,
        subtitle: String,
        color: Color,
        enabled: Bool = true
    ) -> some View {
        let selected = attachable == role
        return Button {
            attachable = role
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.vertical, 14)
            .padding(.leading, 16)
            .padding(.trailing, 14)
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
                .fill(selected ? color : Color.clear)
                .frame(width: 4)
            }
            .opacity(enabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var invisibleCard: some View {
        Button {
            fixed.toggle()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(SkeletonCanvas.boneInvisible)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Invisible")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(isBase ? "The base point cannot be invisible" : "Not intended for dragging")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                Image(systemName: fixed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fixed ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            )
            .opacity(isBase ? 0.4 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isBase)
        .accessibilityLabel("Invisible")
        .accessibilityAddTraits(fixed ? [.isSelected] : [])
    }

    private func helpRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(decorative: Self.image(icon), scale: 2)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }

    private func helpImage(_ name: String) -> some View {
        Image(decorative: Self.image(name), scale: 1)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private static let applyGreen = Color(red: 0x99 / 255, green: 0xc9 / 255, blue: 0x3c / 255)

    private static func image(_ name: String) -> CGImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        else {
            fatalError("chrome missing \(name).png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "chrome/\(name).png")
        } catch {
            fatalError("chrome could not read \(url.path): \(error)")
        }
    }
}
