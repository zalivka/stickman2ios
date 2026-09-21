# Point attributes dialog

Reusable spec for the **Point attributes** sheet (`EditPointDialog`). Match this when building another dialog.

## Chrome

- Medium-height sheet, drag indicator on, pane `#242530`.
- Top bar, not a nav stack: **white circular Back** (black chevron, light shadow) on the left; **title** immediately after it, 17 semibold white, left-aligned, one line; **Apply** on the right.
- Apply is a **lime capsule** (`#99C93C`), 15 bold **black** text, min width 72, vertical pad 8. Not a full-width bar.
- 3pt orange hairline (`#FC961F`) under the top bar.
- Back dismisses the sheet. On Help, title becomes “Help”, Apply is hidden (clear spacer keeps the title from jumping), Back returns to the form.

## Body

- Scrollable form, 16 side / 18 top / 28 bottom.
- Section labels: 12 bold, `#828282`, **uppercase** (“ATTACH”, “NODE”).
- Choices are **cards**, not radio rows or iOS `Form`:
  - 10pt continuous rounded rect
  - fill white 5% idle, 12% selected
  - 14 vertical / 16 leading / 14 trailing
  - 18pt color disc, then title 16 semibold white + subtitle 13 at 55% white
  - selected: white checkmark on the right + **4pt leading stripe** in the option color
  - disabled: 40% opacity, not tappable
- Attach is a **single-select** of three cards (No / Master / Slave) with bone colors: cyan, green, red.
- Node is one **toggle card** (Invisible, grey disc); checkmark.square vs empty square, not a system Toggle.
- Help is a last card: “Help” + chevron.right, no disc, same 10pt card, 6% white fill.

## Help page

- Same sheet, same top bar.
- Icon+text rows, then full-width rounded screenshots, a 1pt 18% white rule, then Invisible copy.

## What not to copy

- No Cancel+Apply pair of equal-width bars.
- No system List/InsetGrouped.
- Title is not centered between the buttons — it sits next to Back.
- Destructive/secondary actions stay as cards in the scroll, not in the top bar.

Range setup is the opposite pattern (centered title, Cancel left / Apply right as rectangular blocks). Point attributes is the one with Back circle + lime capsule + orange rule + selectable cards.
