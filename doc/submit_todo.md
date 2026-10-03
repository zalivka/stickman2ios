# App Store submit TODO — at_elements

## 1. Crash blockers (Guideline 2.1)
- [ ] 1.1 Replace all shipping `fatalError` with graceful errors. Hot spots:
  - [x] `VideoExport`, `JpegVideoAssembler`, `JpegSequenceWriter` — bad frame count, missing jpeg, encode/write failures report `exportFailed` instead of crashing
  - [x] `SavedScenes` / `SavedSceneThumbProvider` — unreadable archive, bad `model.xml`, or missing thumb is skipped; thumb load returns a normal failure
  - [ ] `LandingScreen` version string and `chrome/*.png` still `fatalError` (testdata JSON crashes are `#if DEBUG`)
  - [ ] `SceneEditorScreen`, `SkeletonScreen`, `BgAnimatorScreen`, `CameraAnimatorScreen`, `SpeedEffectsScreen` (dozens of state asserts). Same pattern in `FullscreenPreviewScreen`, `RangeDialogSheet`, `FBFAnimationSheet`, `SkeletonSaveScreen`
- [ ] 1.2 Add corrupted-file path: bad `ats/ati`, missing thumb, empty frames → toast + empty state, never crash.
- [ ] 1.3 Fuzz-test: import garbage `.ats/.ati`, delete thumbs, 0/1-frame scene, export with 0 frames.

## 2. Plist / privacy / signing
- [ ] 2.1 Add `PrivacyInfo.xcprivacy` (required). Declare `UserDefaults`, file timestamps, no tracking if true.
- [x] 2.2 Done: `ITSAppUsesNonExemptEncryption=false` in `Info.plist` (only exempt SHA-256 + HTTPS). Still answer No/exempt in Connect once.
- [x] 2.3 Done: `UIFileSharingEnabled=false`, recordings moved to `Library/Application Support/BonePaperRecordings` (`BonePaperRecorder.swift`).
- [ ] 2.4 Usage string is done in `Info.plist` and both `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription` settings: "The app saves exported videos to your photo library." Still add privacy nutrition + privacy policy URL in Connect.
- [ ] 2.5 Bump `MARKETING_VERSION / CURRENT_PROJECT_VERSION` (now 1.0 / 1). Confirm bundle id `zalivka.at-elements`, team `2X6F8N8723`.

## 3. Permissions UX
- [x] 3.1 Done: `VideoExport.Phase.failed(Failure)` carries `.photosDenied` vs `.exportFailed`; denied shows "allow in Settings" toast + Open Settings alert.
- [x] 3.2 Done: notifications removed — no mid-export prompt; background/leave cancels the export with an "Export cancelled" toast.
- [x] 3.3 Done: unknown open-in file, failed scene import, failed project save, and failed item copy name the failure. "Illegal symbols" and "Already exists" stay as they were.

## 4. Files / UTIs / background
- [ ] 4.1 Test open-in from Files/Mail for `ats/ati` (`CFBundleDocumentTypes`, `LSSupportsOpeningDocumentsInPlace=false`). Must import or show friendly error.
- [x] 4.2 Done: background or leave mid-export cancels, Export is re-enabled, and "Export cancelled" is shown when the editor is visible again. No background task or notification.
- [ ] 4.3 Check tmp cleanup: `export.mp4`, `frame%04d.jpeg` in tmp/cache don't grow unbounded.

## 5. Export quality
- [ ] 5.1 Confirm `mpeg4 + qscale 1, 60fps` (`JpegVideoAssembler.swift:38-49`) plays in Photos, sane size. The `+1s duration` tail freezes last frame — trim or justify.
- [x] 5.2 Done: bottom progress chip with % + Cancel on the Animation screen; leave/background cancels with "Export cancelled" toast.

## 6. UI / HIG (landscape-only iPhone+iPad)
- [ ] 6.1 Small screens: `LandingScreen` rail 100pt, bias-positioned hex buttons — check SE width for clip/overlap.
- [x] 6.2 Done: dropped `statusBarHidden` + `persistentSystemOverlays(.hidden)` — Home indicator and status bar stay visible.
- [x] 6.3 Done: `UIRequiresFullScreen=true`. iPadOS 26 keeps a fixed scene size and scales the window instead of reflowing the editor. The key is deprecated and a future iPadOS will ignore it.
- [ ] 6.4 Accessibility: custom `.plain` buttons need labels, min 44pt targets, contrast on `#3d3e4c` pane, Dynamic Type where text matters.
- [ ] 6.5 Empty states + confirms: LOAD grid empty, delete background/scene confirm, unsaved-changes guard.
- [ ] 6.6 App size: FFmpegKit xcframework is heavy — check final IPA size, slices stripped.

## 7. Metadata to prepare
- [ ] 7.1 Screenshots: landscape iPhone + iPad (editor, playback, export). Icon + launch screen check.
- [ ] 7.2 Connect: support URL, privacy URL, age rating, category, keywords, "no tracking" if true.
- [ ] 7.3 Reviewer notes: steps New Cartoon → add item → Play → Export → Photos; mention landscape-only, notification optional, no login.

## 8. Pre-submit test matrix
- [ ] 8.1 Fresh install → tutorial → make → save → load → export → Photos.
- [ ] 8.2 Denied photos, denied notifications, airplane, low disk, backgrounded, killed mid-export.
- [ ] 8.3 iOS 17.5 min (current `IPHONEOS_DEPLOYMENT_TARGET`), latest iOS, SE + Max + iPad.
