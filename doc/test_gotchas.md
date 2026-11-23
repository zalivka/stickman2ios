# Test gotchas

UI-test and XCUITest traps found while wiring `at_elementsUITests`
(`CopyFrameUITest`: seed `UITestSeed.ats` from `demo_intro.ats`, LOAD → open →
frame 3 → Copy → Paste ×4 → Save → verify `<frame>` count 9 + 4 = 13).

## UI test target not bound to the app target

`xcodebuild test` fails with `No target application path specified via test
configuration: <XCTestConfiguration ...> targetApplicationPath:(null)
targetApplicationBundleID:(null)`. The test bundle exists, but Xcode does
not know which app it tests.

In `at_elements.xcodeproj/project.pbxproj`:

```pbxproj
TargetAttributes = {
    743A53003054CBF7000CC4A9 = {        /* at_elementsUITests */
        CreatedOnToolsVersion = 26.1;
        TestTargetID = 743A529E3054CBF6000CC4A9;   /* at_elements */
    };
};
```

That attribute is the binding. Xcode 14–17 UI test targets link to the host
app via `TestTargetID = <AppTargetID>` in the **project's**
`PBXProject.attributes.TargetAttributes[UITestTargetID]`. In the
`at_elementsUITests` build configurations set `TEST_TARGET_NAME = at_elements;`
and do **not** set `TEST_HOST` / `BUNDLE_LOADER` when `USES_XCTRUNNER` is
active.

Deleting and recreating the test target does not fix this — a recreated
target inherits the same missing project-level linkage. Only the project
attribute adds it.

## `.accessibilityIdentifier` on a parent masks child identifiers

`MainPanel` had `.accessibilityIdentifier("main panel")` on the outer
`VStack`. XCUITest then reported "No matches found" for every child button
(`main_edit_frame`, `menu_button`, …): the identifier on the parent container
masked the children's identifiers in the accessibility snapshot.

Never put `.accessibilityIdentifier` on a container that owns actionable
children. Each tappable control needs its own identifier.

## First-run tutorial (`onlyPlay`) hides every editor button

On a clean simulator container, `SceneEditorScreen` shows the tutorial
overlay (`simple_tutorial`, `intro_auto_launched` in `UserDefaults`), which
sets `onlyPlay = true` and hides all rail buttons (`opacity(0)`,
`disabled(true)`) — `EDIT FRAME` does not exist for XCUITest.

The `-uitest-seed` hook in `at_elementsApp.swift:seedUITestIfNeeded()` marks
those keys `true` in `UserDefaults` before the editor appears. The test also
taps a `Skip` button if it appears. Any further first-run overlay is the same
class of failure: pre-seed its `UserDefaults` key in the seed hook.

## UI test runner cannot read the app's container

`at_elementsUITests-Runner.app` and `at_elements.app` run in separate
sandboxes on the simulator (`data/Containers/Data/Application/<UUID>/`).
`FileManager.default.urls(for: .applicationSupportDirectory)` inside the
test bundle reads the **runner's** container, so a saved file appears missing
(`XCTAssertNotNil failed - Saved UITestSeed.ats must exist`).

On the simulator the app's files live under the shared device tree, so the
test scans for the newest copy:

```
/Users/zalivka/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/*/Library/Application Support/at_elements/saved/UITestSeed.ats
```

Enumerate every device's app containers and pick the file with the latest
`contentModificationDate`. That reads the bytes the app actually wrote,
independently of in-app state.

## Save name field is pre-filled (`Cartoon_<millis % 1000>`)

`SaveProjectSheet` pre-populates `save_name_field` with a generated name
(`Cartoon_<millis % 1000>`). `saveField.typeText("UITestSeed")` appends, so
the file lands as `Cartoon_369UITestSeed.ats` and the lookup for
`UITestSeed.ats` returns `nil`.

Clear by backspacing over the current value before typing:

```swift
let prefill = saveField.value as? String ?? ""
for _ in prefill {
    app.keys["delete"].tap()
}
saveField.typeText("UITestSeed")
```

## `Data` slice scan: `range(of:)` returns original coordinates

The test counts `<frame` in `model.xml` by repeatedly searching
`xml[cursor...]`:

```swift
let slice = xml[cursor...]
guard let hit = slice.range(of: needle) else { break }
cursor += hit.lowerBound + needle.count   // WRONG
```

`hit.lowerBound` is already in the **original** data's coordinate space —
`Data` slices keep the original `startIndex`. Adding it to `cursor`
double-counts and skips every other match: a 13-frame file counted as 5.

```swift
cursor = hit.upperBound   // correct: end of the match, same coordinates
```

## Long first-screen waits

`LandingScreen` waits on `ManifestBootView` asset-pack loading before the
LOAD tab exists. Default 5s `waitForExistence` timeouts flake there; the
landing LOAD tab, the saved-scene cell, and the editor canvas need 30s.
In-editor controls (menu, save, copy/paste) are fine at 5s.
