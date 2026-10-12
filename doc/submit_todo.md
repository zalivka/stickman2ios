# App Store submit TODO — at_elements

## 1. Crash blockers (Guideline 2.1)
- [x] 1.1 Done: every input-, state-, or pressure-reachable `fatalError` is gone. 299 → 70 live calls, all annotated keeps (each carries a `// bundled resource / bundled pack / Info.plist / platform precondition / unused coder / Core Image` comment so a future sweep leaves them alone). Keep list, all deterministic on first debug run:
  - Bundled resources — chrome/handlers/testdata/fonts/demos PNGs+JSONs (48): `BoilDemoScreen` 8, `StickmanFonts` 4, `ItemChooserPanel` 4, `SkeletonCanvas` 3, `Manifest` 2, `BonesGalleryPanel` 2, `DualNavigationChrome` 2, `EditPointDialog` 2, `FrameOpsPanel` 2, `MainPanel` 2, `PresentUnitsPanel` 2, `SkeletonToolsPanel` 2, `UnitPropertiesPanel` 2, `LandingScreen` 2 (testdata, `#if DEBUG`), `RoadLoopScreen` 2, `ShipBoilScreen` 2, `SpeedEffectsScreen` 2, `DemoSeeder` 2, `ItemLoader` 1.
  - Bundled `.atp` pack boundaries (9): `ExternalPack` 7, `Manifest` 1, `AssetTemplates` 1.
  - Info.plist / bundle metadata (5): `SceneSaver` 2, `XMLWrite` 1, `ItemSaver` 1, `LandingScreen` 1.
  - Application Support preconditions (4): `SceneSaver`, `CustomItems`, `BackgroundStore`, `AssetTemplates`.
  - OS invariants (4): `SkeletonOnion` CI filters 2, `init(coder:)` traps 2 (`SpeedCurveEditor`, `UnitPropertiesPanel`).
  - Loader wave (todo 1–4): `ZipStore` non-throwing facades demolished — every zip read throws `ZipError`; `ModelXML`/`SceneXML`/`AssetsXML`/`BubbleMeta`/`SpeedModifier` serialize throws; `documentBytes -> Data?` (nil = dirty edits); `SceneThumbRenderer`/`FrameRasterizer`/`SkeletonOnion.worldOverlay`/`BonePictureScale.transform` throw into existing toast boundaries; `UnitAssets` 20 → 0 (optional `StoredArchive`/`CGImage`, print+skip on bad paint buffers); missing user backgrounds fall back to scene fill.
  - Model/UI wave (todo 5): tween storages (17) validate-and-repair (`ensureValid` drops invalid spans with `assertionFailure`); `CopyPasteBuffer` (7), `SceneUndo` (4), `FBFAnimation` (6, dead `setIdsFromIndices` removed), `SpeedModifier` (7, malformed pivots degrade to flat speed), interpolators (5), UI gates (~35: `DualNavigation`/`SeekFramesBar`/`VerticalRangeBar` clamp during shrinking-frame-count edits; `AdvancedUnitSheet`/`BoneShiftPreview`/`PictureMove`/`Easing`/`SceneSizes`/`StickmanFonts`/`ItemConstructor`/`ItemChooserPanel`/`UnitPropertiesPanel` assert+continue; dead `Manifest.schedule(_:then:)`/`ResultBox` removed; `PackAlias.resolveUnitName` returns the unresolved name instead of trapping).
- [x] 1.2 Done: bad `ats/ati` (any malformed XML, zip entry, font, animation, tween archive, background ref) throws `SceneLoadError`/`ItemLoadError` and lands in the import toast; missing thumb/archive skips or falls back to fill; save failures (`ZipError`, `BackgroundStore.Failure`) toast and keep the editor open. Empty-frame scenes were already rejected by `SceneXML` validation.
- [ ] 1.3 Fuzz-test: import garbage `.ats/.ati`, delete thumbs, 0/1-frame scene, export with 0 frames. Unblocked by 1.1/1.2 — no crash paths left for garbage input to hit.

## 2. Plist / privacy / signing
- [x] 2.1 Done: `at_elements/PrivacyInfo.xcprivacy`. No tracking. UserDefaults `CA92.1`, file timestamps `C617.1`, system boot time `35F9.1` (boot logs and the recorder clock). Collected data matches Amplitude and Bugsnag: product interaction, device ID, coarse location (analytics, linked); crash data and other data types (app functionality, not linked).
- [x] 2.2 Done: `ITSAppUsesNonExemptEncryption=false` in `Info.plist` (only exempt SHA-256 + HTTPS). Still answer No/exempt in Connect once.
- [x] 2.3 Done: `UIFileSharingEnabled=false`, recordings moved to `Library/Application Support/BonePaperRecordings` (`BonePaperRecorder.swift`).
- [ ] 2.4 Usage string is done in `Info.plist` and both `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription` settings: "The app saves exported videos to your photo library." Policy page is `site/privacy.html` in the stickman site. In Connect, paste that URL once the site is deployed, and enter nutrition labels with tracking off. Data linked to you: Product Interaction, Device ID, Coarse Location (Analytics). Data not linked: Crash Data, Other Data Types (App Functionality). Photos are not collected. Bugsnag’s own manifest also lists User ID and Product Interaction as not linked and used for app functionality; include those if the Xcode privacy report shows them.
- [x] 2.5 Done: bumped `MARKETING_VERSION` to 1.0 (`CURRENT_PROJECT_VERSION` is 4). Confirmed bundle id `zalivka.animation`, team `2X6F8N8723`.

## 3. Permissions UX
- [x] 3.1 Done: `VideoExport.Phase.failed(Failure)` carries `.photosDenied` vs `.exportFailed`; denied shows "allow in Settings" toast + Open Settings alert.
- [x] 3.2 Done: notifications removed — no mid-export prompt; background/leave cancels the export with an "Export cancelled" toast.
- [x] 3.3 Done: unknown open-in file, failed scene import, failed project save, and failed item copy name the failure. "Illegal symbols" and "Already exists" stay as they were.

## 4. Files / UTIs / background
- [ ] 4.1 Test open-in from Files/Mail for `ats/ati` (`CFBundleDocumentTypes`, `LSSupportsOpeningDocumentsInPlace=false`). Must import or show friendly error.
- [x] 4.2 Done: background or leave mid-export cancels, Export is re-enabled, and "Export cancelled" is shown when the editor is visible again. No background task or notification.
- [x] 4.3 Done: frames live in one `tmp/export_jpegs/` directory and are removed when an export ends and again at the start of the next one. `export.mp4` is a single file, replaced on the next export. Neither grows.

## 5. Export quality
- [ ] 5.1 Confirm `mpeg4 + qscale 1, 60fps` (`JpegVideoAssembler.swift:38-49`) plays in Photos, sane size. The `+1s duration` tail freezes last frame — trim or justify.
- [x] 5.2 Done: bottom progress chip with % + Cancel on the Animation screen; leave/background cancels with "Export cancelled" toast.

## 6. UI / HIG (landscape-only iPhone+iPad)
- [ ] 6.1 Small screens: `LandingScreen` rail 100pt, bias-positioned hex buttons — check SE width for clip/overlap.
- [x] 6.2 Done: dropped `statusBarHidden` + `persistentSystemOverlays(.hidden)` — Home indicator and status bar stay visible.
- [x] 6.3 Done: `UIRequiresFullScreen=true`. iPadOS 26 keeps a fixed scene size and scales the window instead of reflowing the editor. The key is deprecated and a future iPadOS will ignore it.
- [ ] 6.5 Confirms: delete background or custom item asks first. Unsaved-changes guard is already in the editor (Save / Don’t Save / Cancel).
- [ ] 6.6 App size: FFmpegKit xcframework is heavy — check final IPA size, slices stripped.

## 7. Metadata to prepare
- [x] 7.1 Icon installed (`Assets.xcassets/AppIcon.appiconset/AppIcon.png`, 1024x1024 sRGB, opaque). Screenshots: landscape iPhone + iPad (editor, playback, export). Launch screen check.
- [ ] 7.2 Connect: support URL, privacy URL, age rating, category, keywords, "no tracking" if true.
- [ ] 7.3 Reviewer notes: steps New Cartoon → add item → Play → Export → Photos; mention landscape-only, notification optional, no login.

## 8. Pre-submit test matrix
- [ ] 8.1 Fresh install → tutorial → make → save → load → export → Photos.
- [ ] 8.2 Denied photos, denied notifications, airplane, low disk, backgrounded, killed mid-export.
- [ ] 8.3 iOS 17.5 min (current `IPHONEOS_DEPLOYMENT_TARGET`), latest iOS, SE + Max + iPad.
