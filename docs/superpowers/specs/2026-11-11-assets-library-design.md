# iOS Assets Library Design

**Date:** 2026-11-11
**Android reference:** `AssetsLibraryActivity.java`, `ImageLibraryRepository.java`, `SoundEffectsRepository.java`, `BgChooserFragment.java`, `BgPresenter.java`, `AudioActivity.java`

## Goal

Port Android's `AssetsLibraryActivity` to iOS (`at_elements`) so users can import, manage, and pick:
1. **Images** for backgrounds from `BgChooserSheet` (bone picture picking and crop/sequence support deferred).
2. **Sound Effects** for the scene audio palette from `AudioScreen`.
3. **Debug Browse Mode** reachable from the main editor's `SideMenu` (`#if DEBUG`, row titled `"Assets"`), exposing both categories in a single view.

---

## Architecture & Components

### 1. `ImageLibrary` (`Shared/Loaders/ImageLibrary.swift`)

Mirrors Android `ImageLibraryRepository` for single raster images.

- **Directory:** `Application Support/at_elements/image_library/` (with an optional override parameter in internal methods for unit test isolation).
- **Constants:**
  - `maxDimension = 2048`
  - `thumbMaxDimension = 256`
- **Files per entry:**
  - `<id>.png` — full image (downscaled preserving aspect ratio so `max(width, height) <= 2048`, with `UIImage` orientation normalized to `.up`).
  - `<id>_thumb.png` — thumbnail (`max(width, height) <= 256`).
  - `<id>` is allocated from current epoch milliseconds (`Int((Date().timeIntervalSince1970 * 1000).rounded(.towardZero))`), incrementing by 1 if a file with that id already exists.
- **Model:**
  ```swift
  struct Entry: Identifiable, Equatable {
      var id: String
      var mainURL: URL
      var thumbURL: URL
  }
  ```
- **Operations:**
  - `static func list(in directory: URL? = nil) throws -> [Entry]`: lists `<id>.png` files (excluding `*_thumb.png`), regenerates `<id>_thumb.png` if missing, and sorts descending by `id` (newest first).
  - `static func ingest(data: Data, in directory: URL? = nil) throws -> Entry`: decodes image, normalizes orientation, downscales to `maxDimension`, encodes PNG and thumbnail PNG, writes both atomically, and cleans up on failure.
  - `static func ingest(url: URL, in directory: URL? = nil) throws -> Entry`: reads security-scoped or local file `Data` and delegates to `ingest(data:in:)`.
  - `static func delete(id: String, in directory: URL? = nil) throws`: validates `id` (non-empty, no `/`), removes `<id>.png` and `<id>_thumb.png`.
- **Errors (`ImageLibrary.Failure`):**
  - `.invalidIdentifier(String)`
  - `.unreadableImage(String)`
  - `.encodeFailed(String)`
  - `.ioFailed(String, Error)`

---

### 2. `AudioFiles` Extensions (`Shared/Loaders/AudioFiles.swift`)

Extends the existing `AudioFiles` sound library to support user import, deletion, and newest-first ordering matching `SoundEffectsRepository`.

- **Directory:** `Application Support/at_elements/sounds/`
- **Constants:**
  - `maxSoundFileBytes = 20 * 1024 * 1024` (20 MB, matching Android `AudioUtils.MAX_SOUND_FILE_BYTES`)
  - `supportedExtensions = SceneAudioArchive.supportedExtensions` (`["wav", "mp3", "m4a", "ogg"]`)
- **Operations:**
  - `static func ingest(url: URL, in directory: URL? = nil) throws -> LibraryEntry`:
    1. Verifies lowercase file extension is in `supportedExtensions`; otherwise throws `Failure.unsupportedFormat`.
    2. Reads file attributes / data; if size `<= 0`, throws `Failure.emptyFile`; if size `> maxSoundFileBytes`, throws `Failure.fileTooLarge`.
    3. Allocates millisecond `<id>` (incrementing on collision) and copies bytes to `<id>.<ext>`.
    4. Probes duration via `durationMs(url: dest)`. If probing throws or returns `<= 0`, deletes `<id>.<ext>` and throws `Failure.unreadableAudio`.
    5. Extracts display name from `url.deletingPathExtension().lastPathComponent` (trimmed; falls back to `<id>` if empty) and writes UTF-8 `<id>.name`.
    6. Calls `invalidateLibrary()` and returns the constructed `LibraryEntry`.
  - `static func delete(audioId: String, in directory: URL? = nil) throws`:
    1. Validates `audioId` (non-empty, no `/`).
    2. Removes matching `<audioId>.<ext>` and `<audioId>.name` files from the library directory.
    3. Calls `invalidateLibrary()`.
  - **Ordering:** `readLibrary()` sorts entries by modification date / `audioId` descending (newest first, matching Android `SoundEffectsRepository.list()`) instead of `durationMs` descending.
  - **Dead-code removal:** Remove `alwaysInPalette` and `testPaletteEntries()` from `AudioFiles` (and `seedTestPalette()` from `AudioScreen`), since `AudioFiles.seedLibrary()` already seeds `notif.wav`, `mac.mp3`, `rec.mp3`, and `say_wifi.wav` into `sounds/` where they appear in `AssetsLibrarySheet` ready to be picked.

---

### 3. `AssetsLibrarySheet` (`at_elements/Screens/AssetsLibrarySheet.swift`)

A unified SwiftUI sheet matching Android `AssetsLibraryActivity` and styled consistently with `BgChooserSheet`.

- **Configuration:**
  ```swift
  enum AssetsLibraryMode {
      case browse
      case pickImage((ImageLibrary.Entry) -> Void)
      case pickSound((AudioFiles.LibraryEntry) -> Void)
  }
  ```
- **Categories:**
  - `.images` ("Images")
  - `.sounds` ("Sound Effects")
  - In `.browse`, the left rail (180pt wide, matching `BgChooserSheet`) lists both categories and allows switching.
  - In `.pickImage`, the active category is locked to `.images` and the left category rail is hidden.
  - In `.pickSound`, the active category is locked to `.sounds` and the left category rail is hidden.
- **Navigation Bar:**
  - Leading: `< Back` button calling `onCancel` (stops any playing audio preview first).
  - Title:
    - `.browse`: `"Assets Library"`
    - `.pickImage`: `"Pick Image"`
    - `.pickSound`: `"Pick Sound Effect"`
  - Trailing `+` button:
    - When `.images` is active: opens a confirmation dialog / menu with **"Photo Library"** (`PhotosPicker` matching `.images`) and **"Files"** (`.fileImporter` matching `[.image]`).
    - When `.sounds` is active: opens `.fileImporter` directly matching `[.wav, .mp3, .mpeg4Audio, .audio]` (filtered and validated against `AudioFiles.supportedExtensions`).
- **Grid Content (`LazyVGrid`, adaptive 110pt cells, 8pt spacing):**
  - **Image cell:**
    - Renders `entry.thumbURL` scaled to fit inside a 110×110 rounded card (`Color(white: 0.2)` background).
    - Tap in `.pickImage`: invokes `onPick(entry)`.
    - Tap in `.browse`: no-op.
    - Context menu (long-press): `Delete` (destructive) -> calls `ImageLibrary.delete(id: entry.id)` and reloads items.
  - **Sound cell:**
    - 110×110 rounded rectangle filled with `SceneAudioPalette.colorForName(entry.displayName)`, 2pt stroke (`SceneAudioPalette.chipOutlinePlaying` when playing, `SceneAudioPalette.chipOutline` otherwise).
    - Displays `entry.displayName` (bold, white, centered, up to 2 lines) and duration `String(format: "%.1fs", Double(entry.durationMs) / 1000)` at the bottom.
    - Tap in `.pickSound`: stops preview and invokes `onPick(entry)`.
    - Tap in `.browse`: toggles preview playback via `AudioPlayback`.
    - Context menu (long-press):
      - `Play` / `Stop`: toggles preview playback via `AudioPlayback` (allows previewing sounds before picking in `.pickSound` mode).
      - `Delete` (destructive): stops preview if playing this entry, calls `AudioFiles.delete(audioId: entry.audioId)`, and reloads items.
- **Empty State:**
  - Centered label `"No images yet. Tap + to add."` or `"No sound effects yet. Tap + to add."`.

---

### 4. Call-Site Integrations

#### A. `BgChooserSheet` & `BackgroundStore`
- **`BackgroundStore.savePickedImage(_ imageURL: URL, sceneWidth: CGFloat, sceneHeight: CGFloat) throws -> (bgName: String, image: CGImage, archive: Data)`**:
  - Mirrors Android `BgPresenter.savePickedImageAsBg(uri, true)`:
  - Loads `UIImage` from `imageURL`, normalizes orientation, and downscales to fit within `min(Int(sceneWidth.rounded()), 2048) × min(Int(sceneHeight.rounded()), 2048)` preserving aspect ratio.
  - Encodes `bg.png` and `thumb.png` (`100×100` cover crop) into `bgs/<millis>.zip` and returns `(bgName: "usermade:<millis>", image: cgImage, archive: data)`.
- **`BgChooserSheet`**:
  - Adds an `"Image"` action row in `folderList` (between `"Draw"` and `"Color"`) with fill `#38BDF8` (`Color(red: 0x38/255, green: 0xBD/255, blue: 0xF8/255)`), ink `#07233A` (`Color(red: 0x07/255, green: 0x23/255, blue: 0x3A/255)`), and symbol `"photo.on.rectangle"`.
  - Tapping `"Image"` presents `AssetsLibrarySheet` in `.pickImage` mode.
  - When an `ImageLibrary.Entry` is picked:
    1. Calls `BackgroundStore.savePickedImage(entry.mainURL, sceneWidth: sceneWidth, sceneHeight: sceneHeight)`.
    2. Calls `backgrounds.install(name: saved.bgName, image: saved.image, archive: saved.archive)`.
    3. Dismisses the library sheet and calls `onPick(saved.bgName)`.

#### B. `AudioScreen`
- Tapping the `+` button in `palettePanel` stops any active audio preview and presents `AssetsLibrarySheet` in `.pickSound` mode.
- When an `AudioFiles.LibraryEntry` is picked:
  1. Dismisses `AssetsLibrarySheet`.
  2. If `scene.audio.contains(entry.audioId)` is true, shows toast `"Already in palette"`.
  3. Otherwise commits undo (`commitUndo()`) and calls `scene.audio.addPalette(audioId: entry.audioId, durationMs: entry.durationMs, url: entry.url)`.
- Removes `seedTestPalette()` from `AudioScreen.seedLibraryIfNeeded()`.

#### C. `SideMenu` & `SceneEditorScreen` (`#if DEBUG`)
- `SideMenuAction`: adds `case assets`.
- `SideMenu`: inside `#if DEBUG`, adds `row(.assets, "Assets", "photo.on.rectangle.angled")` above `row(.debug, "Debug", "ladybug")`.
- `SceneEditorScreen`: handles `.assets` in `pickMenu(_:)` by setting `@State private var showingAssetsLibrary = false` to `true`, presenting `AssetsLibrarySheet(mode: .browse, onCancel: { showingAssetsLibrary = false })`.

---

## Error Handling & Testing

- **Loud failures over silent no-ops:**
  - All repository ingest/delete errors throw typed `Failure` enums with descriptive messages and are displayed via the sheet's toast overlay.
  - Failed ingests clean up any temporary/destination files so corrupt or zero-duration entries never pollute the library directories.
- **Unit tests (`at_elementsTests`):**
  - `ImageLibraryTests`:
    - Ingesting a valid image creates `<id>.png` and `<id>_thumb.png` and returns it in `list()`.
    - Ingesting an oversized image (e.g. `3000×1500`) downscales `mainURL` to `2048×1024` and `thumbURL` to `256×128`.
    - Ingesting invalid bytes throws `Failure.unreadableImage` and leaves the directory empty.
    - `delete(id:)` removes both `<id>.png` and `<id>_thumb.png`.
    - `BackgroundStore.savePickedImage` creates a valid `usermade:<id>` zip archive capped at scene/2048 dimensions.
  - `AudioFilesLibraryTests`:
    - Ingesting a valid `.wav`/`.mp3` copies `<id>.<ext>`, writes `<id>.name` with the original stem, and resolves duration.
    - Ingesting an unsupported extension or corrupt audio file throws and leaves no orphan files in the directory.
    - `delete(audioId:)` removes both the audio file and `.name` sidecar.
