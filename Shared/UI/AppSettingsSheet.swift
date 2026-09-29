import SwiftUI

/// App settings. Chrome matches `EditPointDialog` (`doc/good_dialog.md`).
struct AppSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var antialiasing: Bool

    init() {
        _antialiasing = State(initialValue: AppSettings.paperDrawAntialiasing)
    }

    var body: some View {
        VStack(spacing: 0) {
            topPanel
            formBody
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
                Text("App settings")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                applyButton
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
            dismiss()
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
            AppSettings.paperDrawAntialiasing = antialiasing
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
                Text("Paper draw")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SkeletonChrome.toolLabel)
                    .textCase(.uppercase)
                antialiasingCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }

    private var antialiasingCard: some View {
        Button {
            antialiasing.toggle()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(Color(red: 0x99 / 255, green: 0x99 / 255, blue: 0x99 / 255))
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Antialiasing")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Smooth brush and eraser edges")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                Image(systemName: antialiasing ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(antialiasing ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Antialiasing")
        .accessibilityAddTraits(antialiasing ? [.isSelected] : [])
    }

    private static let applyGreen = Color(red: 0x99 / 255, green: 0xc9 / 255, blue: 0x3c / 255)
}
