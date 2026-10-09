# App Store submit TODO — at_elements

## 1. Crash blockers (Guideline 2.1)
- [ ] 1.1 Replace all shipping `fatalError` with graceful errors. Hot spots:
  - [x] `VideoExport`, `JpegVideoAssembler`, `JpegSequenceWriter` — bad frame count, missing jpeg, encode/write failures report `exportFailed` instead of crashing
  - [x] `SavedScenes` / `SavedSceneThumbProvider` — unreadable archive, bad `model.xml`, or missing thumb is skipped; thumb load returns a normal failure
  - [ ] `LandingScreen` version string and `chrome/*.png` still `fatalError` (testdata JSON crashes are `#if DEBUG`)
  - [x] `SkeletonScreen` — all 31: unexpected state → toast + close scene; save failure toasts and keeps the editor open
  - [x] `StickmanScene.swift` — all 73: full throws migration. Mutators/lookups throw `SceneLoadError`; render loops and view bodies use non-fatal optional lookups (`point(optionalId:)`, `currentFrameOrNil`, `unit(namedOrNil:)`) and skip what they cannot draw. Propagated through the Shared layer (SlavesRegistry, UnitAssets, UnitTweenEffects, interpolators, UnitInbetweener, FrameRasterizer, SceneThumbRenderer, InstantiateUnit, ItemConstructor, CopyPasteBuffer, SceneUndo, SkeletonOnion, PresentUnitsPanel, MovieGenerator/JpegSequenceWriter gain a `failure:` callback). `OngoingAnimations.apply` drops only the bad unit's animation per frame. Screens terminate throws at toast+bail boundaries (SceneEditorScreen, SkeletonScreen, BgAnimatorScreen, CameraAnimatorScreen, SpeedEffectsScreen, FBFAnimationSheet, FullscreenPreviewScreen). The screens' own state asserts remain (next item).
  - [ ] `SceneEditorScreen`, `BgAnimatorScreen`, `CameraAnimatorScreen`, `SpeedEffectsScreen` (dozens of state asserts). Same pattern in `FullscreenPreviewScreen`, `RangeDialogSheet`, `FBFAnimationSheet`, `SkeletonSaveScreen`
- [ ] 1.2 Add corrupted-file path: bad `ats/ati`, missing thumb, empty frames → toast + empty state, never crash.
- [ ] 1.3 Fuzz-test: import garbage `.ats/.ati`, delete thumbs, 0/1-frame scene, export with 0 frames.

## 2. Plist / privacy / signing
- [x] 2.1 Done: `at_elements/PrivacyInfo.xcprivacy`. No tracking. UserDefaults `CA92.1`, file timestamps `C617.1`, system boot time `35F9.1` (boot logs and the recorder clock). Collected data matches Amplitude and Bugsnag: product interaction, device ID, coarse location (analytics, linked); crash data and other data types (app functionality, not linked).
- [x] 2.2 Done: `ITSAppUsesNonExemptEncryption=false` in `Info.plist` (only exempt SHA-256 + HTTPS). Still answer No/exempt in Connect once.
- [x] 2.3 Done: `UIFileSharingEnabled=false`, recordings moved to `Library/Application Support/BonePaperRecordings` (`BonePaperRecorder.swift`).
- [ ] 2.4 Usage string is done in `Info.plist` and both `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription` settings: "The app saves exported videos to your photo library." Policy page is `site/privacy.html` in the stickman site. In Connect, paste that URL once the site is deployed, and enter nutrition labels with tracking off. Data linked to you: Product Interaction, Device ID, Coarse Location (Analytics). Data not linked: Crash Data, Other Data Types (App Functionality). Photos are not collected. Bugsnag’s own manifest also lists User ID and Product Interaction as not linked and used for app functionality; include those if the Xcode privacy report shows them.
- [ ] 2.5 Bump `MARKETING_VERSION / CURRENT_PROJECT_VERSION` (now 1.0 / 1). Confirm bundle id `zalivka.animation`, team `2X6F8N8723`.

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
- [ ] 7.1 Screenshots: landscape iPhone + iPad (editor, playback, export). Icon + launch screen check.
- [ ] 7.2 Connect: support URL, privacy URL, age rating, category, keywords, "no tracking" if true.
- [ ] 7.3 Reviewer notes: steps New Cartoon → add item → Play → Export → Photos; mention landscape-only, notification optional, no login.

## 8. Pre-submit test matrix
- [ ] 8.1 Fresh install → tutorial → make → save → load → export → Photos.
- [ ] 8.2 Denied photos, denied notifications, airplane, low disk, backgrounded, killed mid-export.
- [ ] 8.3 iOS 17.5 min (current `IPHONEOS_DEPLOYMENT_TARGET`), latest iOS, SE + Max + iPad.
