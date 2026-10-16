# Disk History

A record of the startup disk's free space over time. Perch reads the disk every 5 minutes and
records one sample per clock hour. The CPU menu shows the free space now and a month of history.
**Disk History…** opens a window with more charts.

## Invariants

- **The history file only grows.** `DiskHistoryStore` appends one line per sample and never
  rewrites or prunes the file. A torn or hand-edited line is skipped when the file loads.
- **One sample per clock hour.** `DiskHistory.isDue` compares UTC hour numbers. A Mac that sleeps
  leaves a gap. It does not record a burst of samples when it wakes.
- **The math stays in `Model/`.** `DiskSample`, `DiskSampleFormat` and `DiskHistory` import neither
  AppKit nor SwiftUI, so `Tests/disk-history-test.swift` compiles them directly.
- **Reads happen off the main actor.** `DiskSpaceReader.read` runs in a detached task, because the
  important-usage figure can take a moment to compute.
- **Disk History has no status item and no setting.** It adds rows to the CPU menu. A year of
  samples is about 430 KB.

## The file

The file is `disk-history.csv` in the channel's Application Support folder, for example
`~/Library/Application Support/com.gstark.perch/disk-history.csv`. **Show File** in the window
reveals it in Finder. Each line is:

```
epoch,total,available,free
```

All values are bytes, and `epoch` is seconds since 1970 in UTC.

| Field | Source | Meaning |
| --- | --- | --- |
| `total` | `volumeTotalCapacity` | The size of the volume. |
| `available` | `volumeAvailableCapacityForImportantUsage` | Free space plus purgeable space. Finder shows this number. |
| `free` | `volumeAvailableCapacity` | Space that no file uses, purgeable files included as used. |

Perch reads `/`. The APFS volumes in one container share its space, so `/` reports the free space
for the Data volume too.

## The menu

The CPU menu has a **Startup Disk** section after the process list:

1. A view item: "412 GB free of 1 TB", the change in used space over the last week, and a
   line of free space over the last 30 days. It appears after the first read.
2. **Disk History…**, which opens the window.

## The window

The window has two segmented pickers.

- **Range**: Day, Week, Month, Year or All.
- **Show**:
  - **Free**: a line of available space. The axis does not start at zero, so small changes show.
  - **Used**: an area of used space, with a dashed line at the volume's capacity.
  - **Change**: one bar per interval. An orange bar above zero means space was used. A green bar
    below zero means space was freed. A bar spans its whole interval, so a gap while the Mac was
    off shows as one wide bar.

`DiskHistory.points` keeps the newest sample in each bucket of the range:

| Range | Bucket |
| --- | --- |
| Day, Week | 1 hour |
| Month | 6 hours |
| Year | 1 day |
| All | Whole days, enough to keep 400 points or fewer |

## Later

Per-folder use is out of scope. A full walk of the disk takes minutes, which an hourly sample
cannot afford.
