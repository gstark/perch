# World Clock

The World Clock converts a time you see on a web page into your own time, and your time into other
cities' times. It has three surfaces, and all of them read time with the calculator's parser,
`CalcZonedMoment` (see [calculator.md](calculator.md#written-moments)):

- **World Clock** is a palette screen. It shows the Mac's own clock first, then every saved clock.
  Type a time (`3pm`, `nov 10 9am tokyo`) and every clock moves to that moment. Type a place, and an
  **Add** row offers it.
- **Convert Time from Clipboard** reads the clipboard and opens World Clock at the moment it finds.
  The clipboard can hold text, an image file, or a bare screenshot.
- The **World Clock** settings pane owns both commands and lists the saved clocks.

## Invariants

- **The Mac's own zone is the default target, and it is always the first row.** Every surface reads
  `Calendar.autoupdatingCurrent`, so a Mac that changes zone converts to the new one without a
  relaunch. The home zone is never stored, and a saved copy of it is dropped from the list.
- **`worldClockZones` stores IANA identifiers, in the order shown.** `WorldClockBoard.normalized`
  drops unknown identifiers and repeats, and the `settings.json` binding uses it as its filter, so
  a hand-edited file cannot break the list.
- **No recognition runs in the app process.** A screenshot goes through `ClipboardTextWorker` and
  the bundled `ClipboardTextHelper`, exactly as Copy Text does (see
  [clipboard.md](clipboard.md#copy-text-from-an-image)). A bare screenshot is written to a temporary
  file for the helper, which reads only files, and removed when the read ends.
- **A clipboard without a time and a zone gives a HUD, never a guess.** `CalcZonedMoment.find`
  requires a clock and a zone, and every word of the lines it joins must parse.
- **`Model/` is Foundation-only.** `world-clock-test` compiles it with all of `Calculator/Model/`.

## Layout

| Path | Role |
| --- | --- |
| `Model/WorldClockBoard.swift` | The rows for one moment, the filter, and the Add candidate |
| `UI/WorldClockCoordinator.swift` | Saved clocks, copying, and the clipboard and screenshot read |
| `UI/WorldClockScreen.swift` | The `PaletteScreen`, and `WorldClockContent`, which builds its rows |
| `UI/WorldClockList.swift` | The list, redrawn each minute through `TimelineView(.everyMinute)` |
| `Settings/WorldClockSettingsView.swift` | The pane: commands, saved clocks, Add a clock |

## The screen

`WorldClockContent.rows` is the one builder for both the screen's selection and the list's drawing,
so the two cannot disagree. A query that `CalcZonedMoment.reference` reads as a moment shows every
clock at it and filters nothing; the header then says "At …" instead of "Now". Any other query
filters the saved clocks by city or identifier, keeps the home row, and adds an **Add** row when
`CalcTimeZone.zone(named:)` resolves it to a zone that is not on the board yet.

| Key | Does |
| --- | --- |
| ↵ | Adds the place on an Add row; copies `12:00 AM Tokyo (Wed, Nov 11)` on a clock |
| ⌘⌫, ⌃X | Removes a saved clock; the home row cannot be removed |
| ⌘K | Copy Time, Remove Clock |

A copy goes through `Paster.copyPlainText` unmarked, so it enters the clipboard history.

## Convert Time from Clipboard

`WorldClockCoordinator.convertClipboardTime` reads in this order, the same order the clipboard poller
uses, because Finder puts a copied file's name on the string type:

1. An image file URL: OCR.
2. Text: `CalcZonedMoment.seed(from:)`.
3. PNG or TIFF data: written to a temporary file, then OCR.

`seed(from:)` returns a single line that the calculator already reads as it is, so
`nov 10 7:36am in tokyo` keeps its target. Otherwise it returns `query(for:)` of the first moment
`find(in:)` sees, for example `2026-11-10 07:36 utc+8`. That spelling is the same in every locale,
and it names the city when the city reads back to the same zone, or else the offset in force at that
moment. The palette opens on World Clock with that query, so the home row shows the converted time.

A second press cancels the OCR helper the first one is waiting on.
