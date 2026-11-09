# Colors

Perch reads a colour wherever one is typed or copied, and picks one off the screen. Three surfaces
share one parser: the clipboard history draws a copied colour as a swatch, the launcher answers a
typed colour with a card the way the calculator does, and **Pick Color** samples a pixel and copies
it.

## Invariants

- **`ColorValue` is the only colour parser, and it stores sRGB.** The clipboard, the launcher card
  and the picker all read it, so no two surfaces can disagree about what counts as a colour or what
  it converts to. A colour is parsed from text on demand and never stored.
- **The picked colour is converted to sRGB before it becomes a `ColorValue`.** `NSColorSampler`
  answers in the display's space, usually Display P3, and reading those components as sRGB gives a
  wrong hex on every wide-gamut screen. `ColorValue(sampled:)` is that conversion.
- **`ColorNotation` is the user's choice and `ColorFormat` is the spelling.** The preference names
  one of four notations, and `ColorNotation.format(for:)` picks the alpha spelling from the colour.
  Nothing else chooses what ↵ copies: `ColorCoordinator.preferredFormat(for:)` is the one call, so
  the card states the text that ↵ copies.
- **The picker has no history of its own.** It copies through `Paster.copyPlainText`, unmarked, so
  the clipboard history records the colour and *Colors Only* lists every pick.
- **`Model/` is Foundation-only.** `clipboard-test` compiles all of `Color/Model/`.

## Layout

| Path | Role |
| --- | --- |
| `Model/ColorValue.swift` | The parser and the sRGB value |
| `Model/ColorSpaces.swift` | Oklab and `oklch()`, both ways |
| `Model/ColorFormat.swift` | The six spellings a colour can be copied as, and their digits |
| `Model/ColorNotation.swift` | The four notations the preference offers |
| `UI/ColorSwatch.swift` | The one place a colour is drawn |
| `UI/ColorCoordinator.swift` | Copy, pick, and the preferred format |
| `Settings/ColorSettingsView.swift` | The Colors pane: the Pick Color command and Copy colors as |

`ColorCard` stays in `Launcher/UI/` and `ColorPreview` in `Clipboard/UI/`, because each belongs to
the screen that shows it.

## Pick Color

`CommandID.pickColor` is a launcher command that the Colors pane owns, so it takes a shortcut there
like any other command. `ColorCoordinator.pickColor()` hides the palette first, because the palette
would cover the pixels under it, and gives focus back to the app below. Then it awaits
`NSColorSampler().sample()`. The sampler shows the system magnifier and needs no Screen Recording
permission.

- Escape cancels, `sample()` returns nil, and nothing is copied.
- A pick copies the colour in the preferred notation and reports `Copied #FF5733` in the HUD.
- A second trigger while the magnifier is open does nothing. The sampler would attach a second
  handler to the open session, so a held chord would copy twice.

## Notation

`colorNotation` (`colors.notation` in settings.json) is Hex, RGB, HSL or Oklch, and Hex is the
default. It decides what the launcher card states, what ↵ on the card copies, and what Pick Color
copies. The card's ⌘K menu still offers every format, with the ↵ chip on the preferred one.

The preference names a notation and not a spelling, because alpha is a fact about the colour. Hex
copies `#FF5733` or `#FF573380`, and HSL adds its alpha argument only when there is alpha. `rgba()`
and `oklch()` state alpha in one spelling, so they have no second form.

The swatch's accessibility label always reads hex. It is a description of the colour, not a copy.

## Formats

`ColorValue` (`Model/`, Foundation-only) takes the CSS spellings people copy: the four hex lengths,
plus `rgb()`/`hsl()`/`oklch()` and their alpha forms in both the comma and CSS4 space-and-slash
syntax. It stores **sRGB components**, so every notation derives from one source rather than a second
parser that can drift from it.

**A colour is rejected rather than approximated**, because a wrong swatch filed under Colors Only
is worse than none. An HSL channel must carry its `%`, or `hsl(120, 100, 50)` clamps to white.
Arguments are counted, so `rgb(255,,87,51)` is malformed rather than three good ones with a hole;
each side of a `/` is counted separately, or `rgb(0 255 / 0.5)` reads an alpha as its blue channel.
`Double` also parses `nan`, `inf` and Swift literals CSS never writes, and every notation ends in
an `Int(_:)` that traps on a non-finite value, so the reject sits at the parse boundary.

`ColorFormat` offers four notations: hex, `rgba()`, `hsl()` and `oklch()`, plus the two spellings
named for their alpha, which `offered(for:)` drops from an opaque colour. That is six rows at most,
four for an opaque one. The digits themselves are `ColorDigits`, private to that file: writing a
colour is the format's business, not the value's. The rest of CSS Color 4 (the space-separated
forms, `hwb()`, `lab()`, `lch()`, `oklab()`) and the `NSColor`/`UIColor`/SwiftUI spellings were all
built and then removed. They restate the same four answers, and a row you scroll past to reach the
one you wanted costs more than it gives. `oklch()` stays as the one perceptual space people write,
and `hsl()` keeps one decimal because whole degrees cost up to 5/255 on the way back.
`clipboard-test` sweeps every offered notation and re-parses it, bar `oklch()`: it states fewer
digits than the channel the sweep compares to.

`ColorSpaces.swift` holds Oklab and its polar form, both ways: matrices and cube roots, no tables.
Oklab is private to it, and `oklch()` is the one thing it exists for. A neutral is stated with no
hue at all, since `atan2` over two rounding errors still names a direction.

## The launcher card

The notations are a menu of their own under the launcher card, and **nowhere else**. A history
entry's ⌘K stays the actions it always was, since converting a colour is not something you reach
for while browsing what you copied. **There is no submenu** either, the palette's menu being one
level deep, so each row states its value through `PopoverMenuItem.detail`, never `shortcut`, which
renders one keycap per character. The rows carry `PopoverMenuIcon.blank`, because a run of rows
under one repeated eyedropper says nothing. The menu keeps the standard `menuWidth`: every notation
fits it, and a menu that widened for its content would jump as rows changed.

`ColorCard` is built from the calculator card's own parts, `LeadCardColumn` and
`.leadCard(selected:)`, so a lead card can't change height or hover with its kind. Its swatch is
**stretched to the value column rather than sized**, since no notation has a fixed height. The card
runs **after** the calculator, which costs nothing: no colour notation is also an expression.

## Detection

`ColorSwatch` is the one place a colour is drawn: row thumbnail, preview and card alike. It draws
over a checkerboard built only when there is alpha to show, so an opaque colour never pays for a
`Canvas` nothing can see. The clipboard preview shows the colour and the copied text and nothing
else.

Detection is narrow by design. Anything past 64 UTF-8 bytes is not a colour. No named colour
(`red`) is recognised, since a bare English word is prose far more often than CSS, and a hex value
must keep its `#`, or `facade` would put a card above the apps. **A colour is never named**:
`#D6D6D6` is a swatch and its digits, never *Silver*. `NSColorList` naming was built, measured and
removed. It knew only the 59 names macOS ships, so most colours read as nothing, and CSS's own
(`gainsboro`) are in no catalog at all.
