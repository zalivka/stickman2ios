# App Store submit TODO — at_elements

## 1. Crash blockers (Guideline 2.1)
- [ ] 1.1 Replace all shipping `fatalError` with graceful errors. Hot spots:
  - `at_elements/Screens/VideoExport.swift:55` (0 files)
  - `at_elements/Screens/JpegVideoAssembler.swift:18,22` (frameCount, missing jpeg)
  - `at_elements/Screens/LandingScreen.swift:259,274,280` (version, chrome png)
  - `at_elements/Screens/SavedScenes.swift:30`, `SavedSceneThumbProvider.swift:25`
  - `SceneEditorScreen`, `SkeletonScreen`, `BgAnimatorScreen`, `CameraAnimatorScreen`, `SpeedEffectsScreen` (dozens of state asserts)
- [ ] 1.2 Add corrupted-file path: bad `ats/ati`, missing thumb, empty frames → toast + empty state, never crash.
- [ ] 1.3 Fuzz-test: import garbage `.ats/.ati`, delete thumbs, 0/1-frame scene, export with 0 frames.

## 2. Plist / privacy / signing
- [ ] 2.1 Add `PrivacyInfo.xcprivacy` (required). Declare `UserDefaults`, file timestamps, no tracking if true.
- [x] 2.2 Done: `ITSAppUsesNonExemptEncryption=false` in `Info.plist` (only exempt SHA-256 + HTTPS). Still answer No/exempt in Connect once.
- [x] 2.3 Done: `UIFileSharingEnabled=false`, recordings moved to `Library/Application Support/BonePaperRecordings` (`BonePaperRecorder.swift`).
- [ ] 2.4 `NSPhotoLibraryAddUsageDescription`: "The app saves exported videos to your photo library." Add privacy nutrition + privacy policy URL in Connect.
- [ ] 2.5 Bump `MARKETING_VERSION / CURRENT_PROJECT_VERSION` (now 1.0 / 1). Confirm bundle id `zalivka.at-elements`, team `2X6F8N8723`.

## 3. Permissions UX
- [x] 3.1 Done: `VideoExport.Phase.failed(Failure)` carries `.photosDenied` vs `.exportFailed`; denied shows "allow in Settings" toast + Open Settings alert.
- [x] 3.2 Done: notifications removed — no mid-export prompt; background/leave cancels the export with an "Export cancelled" toast.
- [ ] 3.3 Replace generic `showToast("error")` in `at_elementsApp.swift:115,118`, `SceneEditorScreen:1179`, `CustomItemsListScreen:154` with actionable strings.

## 4. Files / UTIs / background
- [ ] 4.1 Test open-in from Files/Mail for `ats/ati` (`CFBundleDocumentTypes`, `LSSupportsOpeningDocumentsInPlace=false`). Must import or show friendly error.
- [ ] 4.2 Verify background/leave mid-export cancels cleanly (no hang, "Export cancelled" toast, Export re-enabled). No background task or notification anymore.
- [ ] 4.3 Check tmp cleanup: `export.mp4`, `frame%04d.jpeg` in tmp/cache don't grow unbounded.

## 5. Export quality
- [ ] 5.1 Confirm `mpeg4 + qscale 1, 60fps` (`JpegVideoAssembler.swift:38-49`) plays in Photos, sane size. The `+1s duration` tail freezes last frame — trim or justify.
- [x] 5.2 Done: bottom progress chip with % + Cancel on the Animation screen; leave/background cancels with "Export cancelled" toast.

## 6. UI / HIG (landscape-only iPhone+iPad)
- [ ] 6.1 Small screens: `LandingScreen` rail 100pt, bias-positioned hex buttons — check SE width for clip/overlap.
- [ ] 6.2 `statusBarHidden + persistentSystemOverlays(.hidden)`: verify Home indicator / swipe still reachable, no stuck fullscreen.
- [ ] 6.3 iPad: multitasking / Stage Manager, split view at 1/3 width must not break editor.
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
