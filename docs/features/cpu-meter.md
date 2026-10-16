# CPU meter

The status item is the meter: one bar per core, and a menu that lists the busiest processes.

## Invariants

- **One status item.** `StatusItemController` owns the only `NSStatusItem`, and
  [Git Watch](git-watch.md) adds a badge and a menu row to it. Both clicks open the same menu, and
  `menuNeedsUpdate` rebuilds it each time it opens.
- **The math stays in `Model/`.** `CPULoad`, `ProcessLoad` and `MeterLayout` import neither AppKit nor
  SwiftUI, so `Tests/cpu-meter-test.swift` compiles them directly.
- **Reads happen off the main actor.** `CPUSampler` reads `host_processor_info` and every process's
  `PROC_PIDTASKINFO` once a second in a detached task, then publishes on the main actor.
- **The core count is read at runtime.** Nothing hardcodes it; the layout derives from the sample, and
  the efficiency cluster's size from `hw.perflevel1.logicalcpu`, which an Intel Mac lacks.
- **The look is constants, not settings.** Colors and the efficiency-core opacity live in `MeterImage`,
  geometry and draw order in `MeterLayout`, and the load cuts that pick a colour in `LoadZone`.

## Drawing

Bars stand in one row, each 6 points wide and 16 tall with a 2-point gap. Performance cores draw
first and the efficiency cluster last, at 60% opacity, so the dim group at the right end reads as the
small cores rather than a lighter load. Apple silicon numbers the efficiency cores lowest, which is
why `MeterLayout.order` rotates them to the end instead of drawing in core order. A bar
fills from the bottom with the core's total share (user, nice and system together) over a faint track,
so the row reads as a skyline. The whole bar takes one colour from its `LoadZone`: `systemBlue` under
60%, `systemOrange` under 80%, `systemRed` from there, the same cuts Stats uses. System colours resolve
per appearance, so the bars read on a light and a dark menu bar alike. The user/system split is not
drawn: at menu-bar size two hues in one bar were slivers, and the process menu carries the detail.

## Process list

- `proc_pidinfo` reports CPU time in Mach absolute units, so the sampler times each tick with
  `mach_absolute_time` and the ratio needs no timebase conversion.
- 100% is one core busy for the whole interval, as in Activity Monitor.
- A process with no earlier sample waits one tick, so the menu reads "Measuring…" for the first second.
- A click quits: an app through `NSRunningApplication.terminate()`, anything else with `SIGTERM`.
  Holding Option swaps every row for its alternate, Force Quit (`forceTerminate()` or `SIGKILL`).
- Rows for processes another user owns are shown but disabled; the menu never asks for admin rights.

## Git Watch badge

While a scan runs or a repo is at risk, `GitWatchBadge` draws a symbol and the count, and
`StatusItemController` joins it to the left of the meter in one image. The item grows to the left,
so the meter stays in place. `AppCore` tracks the coordinator's count and scan state and calls
`applyGitWatch()`.

## Menu

Below the process list come **Open Activity Monitor** and, once an address is set in
Settings › Proxmox, **Proxmox…**. See [proxmox.md](proxmox.md). The **Startup Disk** section
follows, with a free-space summary and **Disk History…**. See [disk-history.md](disk-history.md).
