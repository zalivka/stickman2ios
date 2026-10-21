# Error handling — post-fatalError-cleanup policy

Status after the `fatalerror` branch (Oct 2026). Live `fatalError` count: **299 → 71**, all of them annotated
build-integrity keeps. Nothing reachable from user input, file content, memory pressure, or ordinary UI state
can trap anymore.

The one-line rule: **anything the user or the OS can cause must be a value, not a crash.** A bug in our own
logic still screams in debug, and degrades visibly in release.

## The five tiers

### 1. Throw — malformed input and IO failures

Parsing anything user-supplied, and writing anything to user storage, throws a typed error. The type carries a
human-readable `message` and is rendered verbatim into a toast at the screen boundary.

| Type | Thrown by | Boundary |
|---|---|---|
| `SceneLoadError` | `SceneXML.parse`/`serialize`, `SpeedModifier.decode`/`encodeJSON`, `BubbleMeta`, tween storages `encodeArchive`/`importArchive`, `FrameRasterizer`, `SkeletonOnion.worldOverlay`, `BonePictureScale.transform`, `SceneLoader` everything | editor toast + `bail`/stay-open |
| `ItemLoadError` | `ItemLoader` (`.ati` parse), `ModelXML.serialize`, `AssetsXML`, `ItemSaver.save`/`meta` | SkeletonScreen toast, editor stays open |
| `ZipError` | `ZipStore` — every read (`namesThrowing`, `dataThrowing`, `dataAtiThrowing`) and write (`archive`) | wrapped by the loader/saver above |
| `BackgroundStore.Failure` | `saveDrawn`, `replaceDrawn`, `deleteUser`, `archiveURL`, `BackgroundResolver.install` | BgAnimatorScreen toast "Cannot process the background …" |
| `IncomingScene.Failure` / `IncomingItem.Failure` / `IncomingPack.Failure` | open-in-from-Files import (not-a-scene, foreign pack, illegal name, bad `.atp`, read/write) | import toast `Could not install {name}: …` |
| `VideoExport.Failure` | export pipeline → `Phase.failed(.photosDenied / .exportFailed(String))` | "allow in Settings" toast + Open Settings alert |

`ZipStore` has **no non-throwing readers left** — the old `names`/`data(named:)`/`contains` facades were
deleted, so a corrupt zip physically cannot produce a silent empty result. `ZipStore.archive` also rejects
path traversal (`..`), duplicate entries, and oversized names before writing. Every read does the same
checks before inflate allocates: password bit, method other than store/deflate, empty names, `\`, a leading
`/`, a `..` segment, duplicate names, more than 4000 entries, a declared uncompressed entry over 1 GB, or a
declared total over 1 GB. A user `.atp` over 1 GB on disk is rejected before it is read.

Error text funnels through `ItemLoadError.text(_:)`, which unwraps the load types so any boundary can
display any failure with one call.

### 2. Optional + fallback — resource lookups that legitimately miss

A missing thing the app can live with returns `nil`/empty, and the caller has a real fallback:

- `BackgroundAssets.image(for:)` / `archive(for:)` → `nil`: frames referencing a deleted background draw the
  scene fill instead of crashing.
- `UnitAssets.archive(for:)` → `StoredArchive?`, `ensureDrawable`/`createEmptyGalleryBone` → `EdgeAsset?`:
  panels disable the action.
- `UnitAssets.emptyBitmap` → `CGImage?` (allocation failure under memory pressure; caller aborts the edit).
- `SceneSaver.documentBytes` → `Data?`: `nil` means "edits are dirty, don't stamp as saved".
- `ThumbCache.imageIfPresent`, `ItemChooserPanel.packLogo` → `nil` draws a placeholder.
- `HexRGB.parse` → `nil`: SolidBackgrounds drops the pick; the palette falls back.

### 3. Print + skip — batch operations where one bad member must not kill the rest

Directory scans and per-item loops log with `print` and continue:

- `CustomItems.collect()` — unreadable item directory is skipped, the rest of the library loads.
- `BackgroundCatalog.userArchives()/packEntries()` — one broken archive doesn't empty the picker.
- `OngoingAnimations.apply` — drops only the bad unit's animation, per frame.
- `UnitAssets.replaceBitmap` — an invalid paint buffer is dropped, the bone keeps its last good picture.
- `SpeedModifier.fineSpeedValues` — malformed pivot arrays (a 1-point or descending `pivot_points` JSON
  survives decode) degrade to flat 1.0× speed with a log.
- `DemoSeeder` — a demo that fails to copy is skipped; the app still boots.
- `Manifest.reloadAll` — one user `.atp` that fails to parse is left out of the index. The other packs,
  including the rest of the user packs and `@`, still load. The failed names share one toast,
  `Could not load camp.fire, other.pack`. Bundled `packs/*.atp` are not on this path.

### 4. `assertionFailure` + continue — invariant tripwires (debug-only traps)

States that are programmer errors, not user-reachable, but sit in render/edit paths where a release build must
keep going. Debug builds trap; release builds execute the documented continuation:

- **Tween storages**: `ensureValid` *repairs* — drops out-of-range, degenerate, and overlapping spans with an
  assert instead of trapping. `register`/`reconcileInsert`/`reconcileDelete` bad-index guards return `[]`.
- **Editor model**: `CopyPasteBuffer` (empty/out-of-range copy → skip), `SceneUndo` (empty commit → no-op),
  `FBFAnimation` (speed/period out of band → clamp), `PictureMove` (scale ≤ 0 → 1), `Easing.sample`
  (t outside 0...1 or NaN → clamp), `SceneSizes` tick → clamp, interpolators (bad duration/range → endpoint
  or no-op).
- **UI gates**: `DualNavigation`/`SeekFramesBar`/`VerticalRangeBar` *clamp* silently — the bound index can
  momentarily outrun a shrinking frame count during deletes, so these are pure render races, not bugs.
  `AdvancedUnitSheet` clamps the number, `BoneShiftPreview` ignores a degenerate pinch,
  `StickmanFonts.font(unknown key)` → system font, `UnitPropertiesPanel` missing `onSetText` → no-op button,
  `ItemChooserPanel` pack-lookup miss → stays on the current level.
- **Raster/save pre-boundary**: `SceneThumbRenderer.pair`/`itemPair`, `FrameRasterizer.render`,
  `SkeletonOnion`, `BonePictureScale` throw tier-1 errors; the dummy binding setters assert.

Pattern:

```swift
if gapIndex < 0 || gapIndex >= values.count {
    assertionFailure("SpeedModifier gap \(gapIndex) out of \(values.count)")
    return Self.defaultSpeed          // release continuation, always explicit
}
```

### 5. Kept `fatalError` — annotated build-integrity boundaries (71 sites)

Everything left is **deterministic on first debug run**: it fires only if the IPA itself is broken, and no user
action can reach it. Each site carries a comment so a future sweep doesn't "fix" it:

| Annotation | Count | Meaning |
|---|---|---|
| `// bundled resource: a failure here ships broken…` | 48 | `chrome/*.png`, `handlers/*.png`, `fonts/*.ttf`, `testdata/*`, demo packs — static assets shipped in the bundle |
| `// bundled pack: a failure here ships broken…` | 9 | `ExternalPack` `packs/*.atp` discovery + `Manifest`/`AssetTemplates` pack boundaries. These sites only see the app bundle. A user `.atp` is `IncomingPack` / `validateUserPack` and is skipped, never `fatalError` |
| `// Info.plist: a failure here ships broken…` | 5 | `CFBundleVersion`/`CFBundleShortVersionString`/bundle identifier readers |
| `// platform precondition: Application Support always resolves…` | 5 | `FileManager.urls(.applicationSupportDirectory)` in `SceneSaver`, `CustomItems`, `BackgroundStore`, `AssetTemplates`, `InstalledPacks` |
| Core Image filters ship with the OS | 2 | `SkeletonOnion` `CIColorControls`/`CIColorMatrix` |
| Unused `init(coder:)` traps | 2 | `SpeedCurveEditor`, `UnitPropertiesPanel` — views are built in code only |

Design note: consolidating was preferred over spraying `throws`. `PNGImage.cgImage(from:name:)` keeps its
internal fatal because *every* caller is a bundled-static loader; the throw would have propagated a
"can't happen" error through six view layers to a toast that can never show.

## Screen boundaries (where throws die)

- **`SceneEditorScreen.bail(_:)`** — print + toast + `dismiss()`. Used for any throw escaping a mutation,
  undo commit, or save. "A model invariant broke while the editor was live: say so and leave the screen."
- **`SkeletonScreen`** — save failures toast and *keep the editor open* (work isn't lost); unexpected state
  toasts + closes.
- **`BgAnimatorScreen` / `CameraAnimatorScreen` / `SpeedEffectsScreen` / `FullscreenPreviewScreen`** — same
  pattern: toast at the action, screen survives.
- **`VideoExport`** — `Phase.failed` drives the Export button UI; denied photos gets an Open Settings path.
- **Import from Files** (`IncomingScene`/`IncomingItem`/`IncomingPack`) — typed `Failure` with reviewer-facing strings
  ("This file is not a scene. It has no model.xml.", "Could not install camp.fire: missing manifest.xml.").
  A pack that fails does not reload, and does not remove any other pack.

## What this buys at review

- Guideline 2.1 (performance): garbage `.ats`/`.ati`, corrupt zips, deleted backgrounds, 0/1-frame scenes,
  memory pressure during export — all produce toasts or graceful degradation, never crash reports.
- Fuzz testing (submit TODO 1.3) is unblocked: there is no crash path left for malformed input to hit.
- The remaining 71 traps are all provably unreachable in a correctly built IPA, and each is one commented line
  from the build step that would catch it. A user-installed `.atp` that fails to parse toasts its name and
  the other packs still load.

## Adding new code — the checklist

1. Parsing bytes/text the user can supply? → **throw** the tier-1 error type with a `"<Type> <what>: <why>"`
   message. No `try!`, no `fatalError`, no silent `try?` at this layer.
2. Reading a zip? → `ZipStore` throwing API only; the non-throwing facades are gone, don't re-add them.
3. Looking up a resource that may validly be absent? → return optional, give the caller a fallback.
4. Loop over user files? → print + skip the bad member.
5. Guarding a state only our own code can violate? → `assertionFailure` + explicit release continuation
   (return / nil / clamp / no-op). Never bare `assert` (compiled out) and never `fatalError`.
6. Truly bundled-only? → `fatalError` is acceptable **iff** preceded by the standard annotation comment.
