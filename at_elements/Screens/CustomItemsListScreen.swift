import Kingfisher
import SwiftUI
import UIKit

private let slotsDarkGrey = Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255)
private let slotsBrightGreen = Color(red: 0x99 / 255, green: 0xc9 / 255, blue: 0x3c / 255)
private let slotsThumbFill = Color(red: 0xee / 255, green: 0xee / 255, blue: 0xee / 255)
private let templateIconSize: CGFloat = 80

struct CustomItemsListScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CustomItems.Item] = []
    @State private var templates: [Item] = []
    @State private var copyItem: CustomItems.Item?
    @State private var copyName = ""
    @State private var copyError = ""
    @State private var shareItem: CustomItems.Item?

    var body: some View {
        HStack(spacing: 0) {
            slotsGrid
            templatesRail
        }
        .background(slotsDarkGrey.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 17))
                    }
                    .foregroundStyle(.white)
                }
                .tint(.white)
            }
            ToolbarItem(placement: .principal) {
                Text("Custom Items")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .toolbarBackground(slotsDarkGrey, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(.white)
        .onAppear {
            items = CustomItems.collect()
            Task {
                templates = await Manifest.shared.schedule { AssetTemplates.list() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .customItemsDidChange)) { _ in
            items = CustomItems.collect()
        }
        .sheet(item: $copyItem) { item in
            CopyCustomItemSheet(
                name: $copyName,
                error: $copyError,
                onCancel: { copyItem = nil },
                onCopy: { confirmCopy(item) }
            )
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(url: item.url)
        }
    }

    private var slotsGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                ],
                spacing: 2
            ) {
                ForEach(items) { item in
                    CustomItemCell(item: item) {
                        CustomItems.delete(item)
                        items = CustomItems.collect()
                    } onCopy: {
                        copyError = ""
                        copyName = "\(item.name)_copy"
                        copyItem = item
                    } onShare: {
                        shareItem = item
                    }
                }
            }
            .padding(2)
        }
        .frame(maxWidth: .infinity)
    }

    private var templatesRail: some View {
        VStack(spacing: 8) {
            NavigationLink {
                SkeletonScreen(title: "New item", unit: ItemConstructor.blank())
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                    Text("NEW")
                        .font(.system(size: 23, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(width: templateIconSize, height: templateIconSize)
                .background(slotsBrightGreen)
            }
            .buttonStyle(.plain)

            Text("Templates")
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(templates, id: \.systemName) { item in
                        NavigationLink {
                            SkeletonScreen(template: item)
                        } label: {
                            KFImage.dataProvider(TemplatePosterProvider(item: item))
                                .fade(duration: 0.2)
                                .cancelOnDisappear(true)
                                .resizable()
                                .scaledToFit()
                                .frame(width: templateIconSize, height: templateIconSize)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(8)
        .frame(width: templateIconSize + 16)
    }

    private func confirmCopy(_ item: CustomItems.Item) {
        do {
            try CustomItems.copy(item, as: copyName)
            copyItem = nil
            items = CustomItems.collect()
        } catch CustomItems.CopyError.illegalName {
            copyError = "Illegal symbols"
        } catch CustomItems.CopyError.exists {
            copyError = "Already exists"
        } catch {
            copyError = "error"
        }
    }
}

private struct CustomItemCell: View {
    let item: CustomItems.Item
    var onDelete: () -> Void
    var onCopy: () -> Void
    var onShare: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink {
                SkeletonScreen(item: item)
            } label: {
                HStack(spacing: 0) {
                    KFImage.dataProvider(CustomItemThumbProvider(item: item))
                        .fade(duration: 0.2)
                        .cancelOnDisappear(true)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipped()
                        .background(slotsThumbFill)
                        .padding(5)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.name)
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("Created \(createdDate)")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 10)
                    .padding(.top, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .tint(.white)

            Menu {
                itemActions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tint(.white)
        }
        .padding(2)
        .contentShape(Rectangle())
        .contextMenu { itemActions }
    }

    @ViewBuilder
    private var itemActions: some View {
        Button("Delete", role: .destructive, action: onDelete)
        Button("Copy", action: onCopy)
        Button("Share", action: onShare)
    }

    private var createdDate: String {
        Self.dateFormatter.string(from: Date(timeIntervalSince1970: item.mtime))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct CopyCustomItemSheet: View {
    @Binding var name: String
    @Binding var error: String
    var onCancel: () -> Void
    var onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Copy")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            TextField("Name", text: $name)
                .font(.system(size: 22))
                .foregroundStyle(.black)
                .tint(.black)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if !error.isEmpty {
                Text(error)
                    .font(.system(size: 16))
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                Spacer()
                Button("Copy", action: onCopy)
                    .font(.system(size: 17, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0x85 / 255, green: 0xb8 / 255, blue: 0x39 / 255))
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.15))
        .presentationBackground(Color(white: 0.15))
        .presentationDetents([.medium])
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
