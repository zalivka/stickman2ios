---
name: restyle-svg-item
description: >-
  Redraws a Stickman pack item that ships SVG (dog, trex, template.basic)
  in the BonePaper hand-drawn style: 14 px brush, same-colour outline and
  fill, or one stroke for a thin part, plus three line-boil copies. Use when
  the user asks to restyle an SVG item, redraw a pack item like the dog or
  T-Rex, or make an item match the hand-drawn backgrounds.
---

# Restyle an SVG item

Redraw each bone with `hand.py`, the same finger model as the village backgrounds. Do not warp the bitmap and do not add a Metal shader.

**Not this skill**

- A background drawn from scratch (`cartoons.py`, `cartoons2.py`) — there is no source SVG.
- Boiling a finished `session.json` (`boil.py`) — the strokes already exist.
- Boiling the original SVG without redrawing it (`item_boil.py`) — that keeps the thin Kurwa outline.
- Turning the result into a real `.ati`. That was deliberately not done.

Worked results: dog at 269 page px, T-Rex at 300. Findings live in `doc/bone-paper-recording.md` under "Line boil".

## Facts

| Fact | Detail |
|------|--------|
| Script | `tools/bonepaper_gen/item_restyle.py`. Run it. Do not reimplement the hand model. |
| Python | `tools/bonepaper_gen/.venv/bin/python` (Pillow + shapely). Plain `python3` has neither. |
| Input | One path per `edgeAsset`, absolute `M`/`C`/`z`, `fill-opacity` 1. Dog and T-Rex qualify. |
| Refuse | More than one path per part, or fills/strokes at opacity 0 (`command_scale="auto"`, the shark). The script exits. Do not split paths to force it through. |
| Brush | Stays 14 page px. `display_width` is the item's width on the page, not a zoom. |
| Wide part | Short side ≥ 42 px: outline the simplified corners, one fill tap, same colour as the fill. |
| Thin part | One stroke down the long axis of the minimum rotated rectangle, 6–48 px wide. |
| Outline colour | Omit the optional hex. `#2B2B2B` on the dog ate the head. |
| Output | `<name>_still.png` and `<name>_0.png` `<name>_1.png` `<name>_2.png`, each with a 78 px transparent border (`MARGIN + STROKE_MAX`). |
| Curves | Dropped. The outline is the corners after `simplify(1)`. |

## Workflow

```text
- [ ] 1. Confirm the item is one filled path per bone
- [ ] 2. Pick display_width in page px
- [ ] 3. Run item_restyle.py
- [ ] 4. Look at the still PNG
```

### 1. Confirm

Pack items are `at_elements/packs/<pack>.atp`, entry `items/<name>.ati`. Each `edgeAsset` with `state="0"` must have `svg="svg/v_<id>_state_0.svg"` and that file must contain exactly one `<path>` whose fill is opaque.

```bash
cd tools/bonepaper_gen
.venv/bin/python -c "
import zipfile, io, re, sys
z = zipfile.ZipFile(sys.argv[1])
inner = zipfile.ZipFile(io.BytesIO(z.read(sys.argv[2])))
for tag in re.findall(r'<edgeAsset ([^>]*)/>', inner.read('assets.xml').decode()):
    a = dict(re.findall(r'(\w+)=\"([^\"]*)\"', tag))
    if a.get('state','0') != '0':
        continue
    s = inner.read(a['svg']).decode()
    print(a['bm'], 'paths', len(re.findall(r'<path ', s)))
" ../../at_elements/packs/template.basic.atp items/dog.ati
```

Shared SVGs (the T-Rex reuses 8 files across 13 bones) are fine: each bone is redrawn on its own.

### 2. Width

`display_width` is how wide the rest pose should be on a 640×480 page. The dog was 269 (42% of the page). The T-Rex was 300. A different width needs a new run; the brush does not scale afterwards.

### 3. Run

```bash
cd tools/bonepaper_gen
.venv/bin/python item_restyle.py \
  ../../at_elements/packs/template.basic.atp dog.ati out/restyle dog 269
```

Stdout names each part `outline + fill` or `stroke Npx`. A leak in a boil copy is re-rolled; three failures stop the script. Do not loosen the check.

### 4. Look

Open `out/restyle/<name>_still.png`. Wide parts have a wobbly outline in their own colour and a fill under it. Thin parts are one sausage stroke. Corners stay corners; a knob on a tip means something pushed points along their normals — `item_restyle.py` does not do that.

Do not build the iOS app unless the user asks. Do not write the parts back into an `.ati`.
