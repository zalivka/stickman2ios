import SwiftUI
import UIKit

struct SkeletonSaveScreen: View {
    var onClose: () -> Void
    var onSaveNew: (String) -> Void
    var onOverwrite: (CustomItems.Item) -> Void

    @State private var name = ItemSaver.freeName()
    @State private var nameError = ""
    @State private var items: [CustomItems.Item] = []
    @State private var pending: CustomItems.Item?
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("Name")
                    TextField("Name", text: $name)
                        .font(.system(size: 22))
                        .foregroundStyle(.black)
                        .tint(.black)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .disabled(saving)
                        .onChange(of: name) { _, _ in
                            refreshNameError()
                        }
                    if !nameError.isEmpty {
                        Text(nameError)
                            .font(.system(size: 16))
                            .foregroundStyle(.red)
                    }
                    sectionTitle("Items")
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 2),
                            GridItem(.flexible(), spacing: 2)
                        ],
                        spacing: 2
                    ) {
                        ForEach(items) { item in
                            itemCell(item)
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
        .onAppear {
            items = CustomItems.collect()
            refreshNameError()
        }
        .onReceive(NotificationCenter.default.publisher(for: .customItemsDidChange)) { _ in
            items = CustomItems.collect()
            refreshNameError()
        }
        .alert(overrideTitle, isPresented: overrideShown) {
            Button("Yes") {
                guard let item = pending else {
                    fatalError("SkeletonSaveScreen override with no item")
                }
                pending = nil
                saving = true
                onOverwrite(item)
            }
            Button("Cancel", role: .cancel) {
                pending = nil
            }
        }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackCircleButton(action: onClose)
                    .disabled(saving)
                Text("Save")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: applyNew) {
                    Text("Apply")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(minWidth: 72)
                        .padding(.vertical, 8)
                        .background(SkeletonChrome.boneNew)
                        .clipShape(Capsule())
                        .opacity(canApply ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!canApply)
                .accessibilityLabel("Apply")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
            SkeletonChrome.bonesAccent.frame(height: 3)
        }
        .background(SkeletonChrome.pane)
    }

    private func itemCell(_ item: CustomItems.Item) -> some View {
        Button {
            if saving {
                return
            }
            pending = item
        } label: {
            HStack(spacing: 0) {
                SaveItemThumb(item: item)
                    .frame(width: 60, height: 60)
                    .clipped()
                    .background(Color(red: 0xee / 255, green: 0xee / 255, blue: 0xee / 255))
                    .padding(5)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name)
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Created \(createdDate(item))")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.leading, 10)
                .padding(.top, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(2)
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .opacity(saving ? 0.4 : 1)
        .accessibilityLabel(item.name)
    }

    private func createdDate(_ item: CustomItems.Item) -> String {
        Self.dateFormatter.string(from: Date(timeIntervalSince1970: item.mtime))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(SkeletonChrome.toolLabel)
            .textCase(.uppercase)
    }

    private var overrideShown: Binding<Bool> {
        Binding(
            get: { pending != nil },
            set: { shown in
                if !shown {
                    pending = nil
                }
            }
        )
    }

    private var overrideTitle: String {
        let label = pending?.name ?? ""
        return "Override \(label)?"
    }

    /// Android `SaveDialog` with advanced mode off: empty is silent, illegal symbols, then an existing `.ati`.
    private func refreshNameError() {
        if name.isEmpty {
            nameError = ""
            return
        }
        if !SceneSaver.isGoodFileName(name) {
            nameError = "Illegal symbols"
            return
        }
        let stored = name.replacingOccurrences(of: " ", with: "_")
        let url = CustomItems.directory().appendingPathComponent("\(stored).\(CustomItems.ext)")
        if FileManager.default.fileExists(atPath: url.path) || nameTaken(stored) {
            nameError = "The file already exists"
            return
        }
        nameError = ""
    }

    /// The grid shows `name`, which can differ from the `.ati` filename.
    private func nameTaken(_ stored: String) -> Bool {
        let typed = name.lowercased()
        let file = stored.lowercased()
        return items.contains { item in
            item.systemName.lowercased() == file
                || item.name.lowercased() == typed
                || item.name.lowercased() == file
        }
    }

    private var canApply: Bool {
        !saving && !name.isEmpty && nameError.isEmpty
    }

    private func applyNew() {
        if !canApply {
            return
        }
        saving = true
        onSaveNew(name)
    }
}

private struct SaveItemThumb: View {
    let item: CustomItems.Item
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(white: 0.93)
            }
        }
        .task(id: item.cacheKey) {
            let url = item.url
            let loaded = await Task.detached(priority: .userInitiated) {
                Self.load(url)
            }.value
            image = loaded
        }
    }

    private static func load(_ url: URL) -> UIImage? {
        let zip: Data
        do {
            zip = try Data(contentsOf: url)
        } catch {
            return nil
        }
        if !ZipStore.contains("thumb.png", in: zip) {
            return nil
        }
        return UIImage(data: ZipStore.data(named: "thumb.png", in: zip))
    }
}
