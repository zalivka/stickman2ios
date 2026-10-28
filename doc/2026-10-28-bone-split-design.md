# Bone Split Tool — iOS Skeleton Editor Design Spec

## Overview

The **Bone Split** tool lets the user split an existing bone (`S → B`) into two connected bones (`S → A` and `A → B`) and simultaneously split its attached bitmap into two overlapping pieces around a circular joint disc of user-controlled radius \(R\) centered at the split point \(A\).

Because both resulting bitmaps include the circular disc \(D(A, R)\) centered at the new joint \(A\), rotating `A → B` around \(A\) produces a smooth round hinge without gaps or sharp corner seams.

---

## 1. Entry Point & Mode Lifecycle

### Entry in `SkeletonBonesTools` (`BONES` panel)
- Add a **Split** button to `SkeletonBonesTools` in `Shared/UI/SkeletonToolsPanel.swift`.
- Enabled when `selectedPointId` has an `upperEdge` (`S → B`, i.e., a non-base point is selected) and the bone length is at least `2 * BoneSplitDraft.minEndMargin` (`20` item-pixel units).
- Tapping **Split** enters Split mode by creating a `BoneSplitDraft` on `SkeletonEditSession` / `SkeletonScreen`.

### Initial `BoneSplitDraft` State
- `edgeFrom`: \(S\), `edgeTo`: \(B\)
- `t`: `0.5` (midpoint along `S → B`), clamped to keep \(A\) at least `minEndMargin = 10` item-pixel units away from \(S\) and \(B\):
  \[
  t \in \left[\frac{10}{L},\; 1 - \frac{10}{L}\right]
  \]
- `radius`: default joint radius in item-pixel units.
  - If the edge has a bitmap: scan the bitmap column at \(x_{\text{split}} = -x_{\text{offset}} + t \cdot L\) for the first and last pixels with \(\alpha > 16\), set `radius = clamp((lastY - firstY) / 2, 8, min(L / 2, 120))`.
  - If the column is empty or the edge has no bitmap: `radius = clamp(L * 0.18, 8, 60)`.

### Mode Cancellation & Exit
- Split mode exits without changes when:
  - User taps **Cancel** on the floating pill.
  - User switches `toolsPanel` away from `.bones`, opens the side menu, or starts `boneCreateHoldMode`.
  - User taps a different skeleton point on the canvas outside the split gizmo handles.
- Undo is **not** pushed during gizmo adjustments; a single undo snapshot (`prepareUndo(includeAssets: true)`) is pushed when the user taps **Apply**.

---

## 2. Canvas Gizmo & Touch Interaction

### Visual Overlay (`SkeletonCanvas` in `.skeleton` mode)
When `editSession.boneSplit != nil`, `SkeletonCanvas` draws the split gizmo over the target bone `S → B`:
1. **Cut Line**: A dashed line through split point \(A\) perpendicular to `S → B`, spanning diameter \(2R\).
2. **Joint Circle**: A translucent fill (`Color(red: 1, green: 0.69, blue: 0.23).opacity(0.22)`) and solid stroke (`2 pt`, orange/amber) of radius \(R_{\text{screen}} = R \cdot \text{unit.scale} \cdot \text{layout.scale}\) centered at \(A_{\text{screen}}\).
3. **Center Handle**: Filled circle at \(A_{\text{screen}}\) (`radius: 7 pt`, white fill with orange stroke).
4. **Rim Handle**: Filled handle on the circle perimeter along the perpendicular normal \(+\hat{n}\) at distance \(R_{\text{screen}}\) from \(A_{\text{screen}}\) (`radius: 7 pt`, white fill with orange stroke).

### Touch Handling in `SkeletonCanvas`
While `editSession.boneSplit != nil`:
- **Dragging the Center Handle** (hit radius `28 pt`): projects the finger's scene point orthogonally onto segment `S → B` and updates `t`, clamped to `[minEndMargin / L, 1 - minEndMargin / L]`.
- **Dragging the Rim Handle** (hit radius `28 pt`): sets `radius` to the distance from \(A\) to the finger in item-pixel units, clamped to `[minRadius (4), maxRadius (min(L * 0.9, 125))]`.
- **Two-finger Pinch**: scales `radius` by the pinch factor within the same `[minRadius, maxRadius]` bounds (while still allowing two-finger pan).
- **Empty Canvas Drag**: pans the canvas as usual.

### Floating Confirmation Pill (`SkeletonScreen`)
- Displayed at bottom-center of `SkeletonScreen` while `boneSplit != nil`:
  - **Cancel** button (secondary dark capsule) and **Apply** button (accent orange capsule).

---

## 3. Skeleton Topology Mutation (`StickmanUnit.splitEdge`)

`StickmanUnit.splitEdge(from: Int, to: Int, t: CGFloat) throws -> Int` performs the structural split:

1. Validate that edge `from → to` (`S → B`) exists, \(B\) has `parentId == S`, and \(0 < t < 1\).
2. Allocate `newId = (points.map(\.id).max() ?? 0) + 1`.
3. Compute split coordinates in scene space:
   \[
   A_x = S_x + t(B_x - S_x), \quad A_y = S_y + t(B_y - S_y)
   \]
4. Insert `StickmanPoint(id: newId, x: A_x, y: A_y, isBase: false, parentId: S)` (with `attachable = .none`, `fixed = false`).
5. Update point \(B\)'s `parentId` from \(S\) to `newId`. All other properties of \(B\) (`attachable`, `fixed`, `semanticName`, children of \(B\)) remain unchanged.
6. Call `try link()` to rebuild `edges` and validate the tree.
7. Return `newId` (\(A\)), which becomes the new `selectedPointId`.

---

## 4. Bitmap & Sidecar Buffer Splitting (`BonePictureSplit` & `UnitAssets`)

### Coordinate Space & Clipping Masks
For an `EdgeAsset` on `S → B` with length \(L = \text{hypot}(B - S) / \text{unit.scale}\) and split distance \(d = t \cdot L\):
- In the bitmap's pixel space (`0..<W`, `0..<H`):
  - Bone start \(S\) is at \((-x_{\text{offset}}, -y_{\text{offset}})\).
  - Split point \(A\) is at \((x_{\text{split}}, y_{\text{split}}) = (-x_{\text{offset}} + d,\; -y_{\text{offset}})\).
  - Joint radius is \(R\) pixels.

Using CoreGraphics vector clipping (`CGContext.addPath` + `CGContext.clip()` with winding rule `.nonZero`):
- **Proximal clip path (`S → A`)**:
  - `CGRect(x: 0, y: 0, width: xSplit, height: H)`
  - `CGPath(ellipseIn: CGRect(x: xSplit - R, y: ySplit - R, width: 2 * R, height: 2 * R))`
- **Distal clip path (`A → B`)**:
  - `CGRect(x: xSplit, y: 0, width: max(0, W - xSplit), height: H)`
  - `CGPath(ellipseIn: CGRect(x: xSplit - R, y: ySplit - R, width: 2 * R, height: 2 * R))`

### Tight-Crop Bounding Boxes & Offsets
- **Proximal (`S → A`)**:
  - Horizontal bounds: `cropMinX = 0`, `cropMaxX = min(W, Int(ceil(xSplit + R)))`.
  - If `cropMaxX < 1`, fall back to a `1 × 1` transparent pixel at `S`.
  - Joint stays at \(S\):
    \[
    x_{\text{offset,prox}} = x_{\text{offset}} + \text{cropMinX} = x_{\text{offset}}, \quad y_{\text{offset,prox}} = y_{\text{offset}}
    \]
- **Distal (`A → B`)**:
  - Horizontal bounds: `cropMinX = max(0, Int(floor(xSplit - R)))`, `cropMaxX = W`.
  - If `cropMaxX - cropMinX < 1`, fall back to a `1 × 1` transparent pixel at `A`.
  - Joint moves to \(A\) \((x_{\text{split}}, y_{\text{split}})\):
    \[
    x_{\text{offset,dist}} = \text{cropMinX} - x_{\text{split}} = \text{cropMinX} + x_{\text{offset}} - d, \quad y_{\text{offset,dist}} = y_{\text{offset}}
    \]

### `paintBuffer` (`2×` Sidecar) Preservation
If `asset.paintBuffer` is present and valid (`2W × 2H`, where `sample = BonePaperDocument.sample = 2`):
- Run the exact same clip and crop on the decoded buffer image with `xSplit * sample`, `ySplit * sample`, `R * sample`, and exact doubled crop bounds `cropMinX * sample ..< cropMaxX * sample`.
- Because `cropMinX` and `cropMaxX` are integers in `1×` space, doubling them guarantees the cropped buffer dimensions are strictly `sample` times the cropped `1×` bitmap dimensions (`width * 2`, `height * 2`), satisfying `validatedBuffer` without rounding drift.

### Multi-State Assets, Draw Order, and Loose Gallery Copy
When `UnitAssets.splitEdgeAssets(from: S, mid: A, to: B, unitName: String, splitDistance: CGFloat, radius: CGFloat)` executes:
1. If `S → B` has no attached assets, nothing in `UnitAssets` changes (only the skeleton topology splits).
2. If `S → B` has attached assets (across one or more states / flipped keys):
   - Remove the `EdgeKey(unitName, S, B, ...)` entry from `edgeAssets`.
   - Retain the original default-state `EdgeAsset` in `looseBones[originalBmName]` (with `start = -1, end = -1`) if no other edge still references `originalBmName`, so the unsplit artwork remains available in the right-hand gallery.
   - Shift all existing assets with `weight > originalWeight` up by `+1` to make room for the two halves.
   - Insert proximal assets under `EdgeKey(unitName, S, A, ...)` with `weight = originalWeight` and new unique `bmName` (`uniqueBmName(start: S, end: A)`).
   - Insert distal assets under `EdgeKey(unitName, A, B, ...)` with `weight = originalWeight + 1` (drawn on top of proximal) and new unique `bmName` (`uniqueBmName(start: A, end: B)`).
   - Clear `svgName` and `commandScale` on the newly cropped bitmap assets since their geometry no longer matches the original unsplit SVG entry.

---

## 5. Files Affected

- `Shared/Model/BonePictureSplit.swift` (new): Pure CoreGraphics clipper/cropper for `1×` bitmap and `2×` `paintBuffer`, returning proximal and distal `Result(image, buffer, xOffset, yOffset)`.
- `Shared/Model/StickmanScene.swift`: Add `StickmanUnit.splitEdge(from:to:t:)`.
- `Shared/Model/UnitAssets.swift`: Add `splitEdgeAssets(from:mid:to:unitName:splitDistance:radius:)`.
- `Shared/UI/SkeletonEditSession.swift`: Hold `BoneSplitDraft` state (`edgeFrom`, `edgeTo`, `t`, `radius`) and helper methods.
- `Shared/UI/SkeletonToolsPanel.swift`: Add `Split` button to `SkeletonBonesTools` and `SkeletonSecondaryContent.bones`.
- `Shared/UI/SkeletonCanvas.swift`: Draw the split circle/cut-line/handles gizmo and route touch/pinch gestures when `editSession.boneSplit != nil`.
- `at_elements/Screens/SkeletonScreen.swift`: Wire the `Split` button, default radius auto-detection, floating `Cancel / Apply` confirmation bar, and `applyBoneSplit()`.
