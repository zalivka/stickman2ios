import BonePaper
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum AssetsLibraryMode {
    case browse
    case pickImage((ImageLibrary.Entry) -> Void)
    case pickSound((AudioFiles.LibraryEntry) -> Void)
}

/// Android `AssetsLibraryActivity`: unified asset store for user images and sound effects.
struct AssetsLibrarySheet: View {
    enum Category: String, CaseIterable, Identifiable {
        case images
        case sounds

        var id: String { rawValue }

        var title: String {
            switch self {
            case .images: return "Images"
            case .sounds: return "Sound Effects"
            }
        }
    }

    var mode: AssetsLibraryMode
    var onCancel: () -> Void

    @State private var selectedCategory: Category
    @State private var images: [ImageLibrary.Entry] = []
    @State private var sounds: [AudioFiles.LibraryEntry] = []
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var activeFileImportKind: Category = .images
    @State private var previewingSoundId: String?
    @State private var toast = ""
    @StateObject private var audioPreview = AudioPlayback()

    private static let thumbSize: CGFloat = 110

    init(mode: AssetsLibraryMode, onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onCancel = onCancel
        switch mode {
        case .browse, .pickImage:
            _selectedCategory = State(initialValue: .images)
        case .pickSound:
            _selectedCategory = State(initialValue: .sounds)
        }
    }

    private var showsCategoryRail: Bool {
        if case .browse = mode {
            return true
        }
        return false
    }

    private var navigationTitleText: String {
        switch mode {
        case .browse:
            return "Assets Library"
        case .pickImage:
            return "Pick Image"
        case .pickSound:
            return "Pick Sound Effect"
        }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if showsCategoryRail {
                    categoryRail
                    Rectangle()
                        .fill(Color(white: 0.35))
                        .frame(width: 1)
                }
                contentPane
            }
            .background(MainPanel.pane.ignoresSafeArea())
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        stopPreview()
                        onCancel()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 17))
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    addButton
                }
            }
            .toolbarBackground(MainPanel.pane, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .overlay {
            if !toast.isEmpty {
                Text(toast)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: reloadAll)
        .onDisappear(perform: stopPreview)
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            selectedPhotoItem = nil
            importPhotoItem(item)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: activeFileImportKind == .images ? [.image] : Self.soundContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch activeFileImportKind {
            case .images:
                handleImageFileImport(result)
            case .sounds:
                handleSoundFileImport(result)
            }
        }
    }

    private static var soundContentTypes: [UTType] {
        var types: [UTType] = [.wav, .mp3, .mpeg4Audio, .audio]
        if let ogg = UTType(filenameExtension: "ogg") {
            types.append(ogg)
        }
        return types
    }

    @ViewBuilder
    private var addButton: some View {
        switch selectedCategory {
        case .images:
            Menu {
                Button {
                    showingPhotoPicker = true
                } label: {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }
                Button {
                    activeFileImportKind = .images
                    showingFileImporter = true
                } label: {
                    Label("Files", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
            }
            .accessibilityLabel("Add image")
        case .sounds:
            Button {
                activeFileImportKind = .sounds
                showingFileImporter = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
            }
            .accessibilityLabel("Add sound")
        }
    }

    private var categoryRail: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Category.allCases) { category in
                    Button {
                        if selectedCategory != category {
                            stopPreview()
                            selectedCategory = category
                        }
                    } label: {
                        Text(category.title)
                            .font(.system(size: 15, weight: selectedCategory == category ? .bold : .regular))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedCategory == category ? Color(white: 0.3) : Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 180)
    }

    @ViewBuilder
    private var contentPane: some View {
        switch selectedCategory {
        case .images:
            if images.isEmpty {
                emptyState("No images yet. Tap + to add.")
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Self.thumbSize, maximum: Self.thumbSize + 20), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(images) { entry in
                            imageCell(entry)
                        }
                    }
                    .padding(8)
                }
            }
        case .sounds:
            if sounds.isEmpty {
                emptyState("No sound effects yet. Tap + to add.")
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Self.thumbSize, maximum: Self.thumbSize + 20), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(sounds) { entry in
                            soundCell(entry)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Color(white: 0.7))
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func imageCell(_ entry: ImageLibrary.Entry) -> some View {
        Button {
            if case .pickImage(let onPick) = mode {
                onPick(entry)
            }
        } label: {
            Group {
                if let uiImage = UIImage(contentsOfFile: entry.thumbURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    Color(white: 0.3)
                }
            }
            .frame(width: Self.thumbSize, height: Self.thumbSize)
            .background(Color(white: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.id)
        .contextMenu {
            Button("Delete", role: .destructive) {
                deleteImage(entry)
            }
        }
    }

    private func soundCell(_ entry: AudioFiles.LibraryEntry) -> some View {
        let isPlaying = previewingSoundId == entry.audioId
        return Button {
            switch mode {
            case .pickSound(let onPick):
                stopPreview()
                onPick(entry)
            case .browse, .pickImage:
                toggleSoundPreview(entry)
            }
        } label: {
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                Text(entry.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Text(String(format: "%.1fs", Double(entry.durationMs) / 1000))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(8)
            .frame(width: Self.thumbSize, height: Self.thumbSize)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SceneAudioPalette.colorForName(entry.displayName))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isPlaying ? SceneAudioPalette.chipOutlinePlaying : SceneAudioPalette.chipOutline,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.displayName)
        .contextMenu {
            Button(isPlaying ? "Stop" : "Play") {
                toggleSoundPreview(entry)
            }
            Button("Delete", role: .destructive) {
                deleteSound(entry)
            }
        }
    }

    // MARK: - Actions

    private func reloadAll() {
        do {
            try AudioFiles.seedLibrary()
        } catch {
            showToast(ItemLoadError.text(error))
        }
        reloadImages()
        reloadSounds()
    }

    private func reloadImages() {
        do {
            images = try ImageLibrary.list()
        } catch {
            showToast(ItemLoadError.text(error))
        }
    }

    private func reloadSounds() {
        sounds = AudioFiles.library()
    }

    private func importPhotoItem(_ item: PhotosPickerItem) {
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    await MainActor.run {
                        showToast("Could not load selected photo")
                    }
                    return
                }
                let entry = try ImageLibrary.ingest(data: data, label: "photo")
                await MainActor.run {
                    reloadImages()
                    if case .pickImage(let onPick) = mode {
                        onPick(entry)
                    }
                }
            } catch {
                await MainActor.run {
                    showToast(ItemLoadError.text(error))
                }
            }
        }
    }

    private func handleImageFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            showToast(error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let entry = try ImageLibrary.ingest(url: url)
                reloadImages()
                if case .pickImage(let onPick) = mode {
                    onPick(entry)
                }
            } catch {
                showToast(ItemLoadError.text(error))
            }
        }
    }

    private func handleSoundFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            showToast(error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let entry = try AudioFiles.ingest(url: url)
                reloadSounds()
                if case .pickSound(let onPick) = mode {
                    stopPreview()
                    onPick(entry)
                }
            } catch {
                showToast(ItemLoadError.text(error))
            }
        }
    }

    private func deleteImage(_ entry: ImageLibrary.Entry) {
        do {
            try ImageLibrary.delete(id: entry.id)
            reloadImages()
        } catch {
            showToast(ItemLoadError.text(error))
        }
    }

    private func deleteSound(_ entry: AudioFiles.LibraryEntry) {
        if previewingSoundId == entry.audioId {
            stopPreview()
        }
        do {
            try AudioFiles.delete(audioId: entry.audioId)
            reloadSounds()
        } catch {
            showToast(ItemLoadError.text(error))
        }
    }

    private func toggleSoundPreview(_ entry: AudioFiles.LibraryEntry) {
        if previewingSoundId == entry.audioId {
            stopPreview()
            return
        }
        stopPreview()
        previewingSoundId = entry.audioId
        audioPreview.play(url: entry.url) {
            previewingSoundId = nil
        }
    }

    private func stopPreview() {
        audioPreview.stop()
        previewingSoundId = nil
    }

    private func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toast == text {
                toast = ""
            }
        }
    }

    @MainActor static func configureBonePaperImagePicker() {
        BonePaperScreen.imagePickerSheetProvider = { onPicked, onCancel in
            AnyView(
                AssetsLibrarySheet(
                    mode: .pickImage { entry in
                        do {
                            let cgImage = try ImageLibrary.decodeForBonePaper(entry: entry)
                            onPicked(cgImage)
                        } catch {
                            onCancel()
                            ToastCenter.show("Failed to load image")
                        }
                    },
                    onCancel: onCancel
                )
            )
        }
    }
}
