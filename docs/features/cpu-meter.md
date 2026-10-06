# CPU meter

The status item is the meter: one cell per core, and a menu that lists the busiest processes.

## Invariants

- **One status item.** `StatusItemController` owns the only `NSStatusItem`. Both clicks open the same
  menu, and `menuNeedsUpdate` rebuilds it each time it opens.
- **The math stays in `Model/`.** `CPULoad`, `ProcessLoad` and `MeterLayout` import neither AppKit nor
  SwiftUI, so `Tests/cpu-meter-test.swift` compiles them directly.
- **Reads happen off the main actor.** `CPUSampler` reads `host_processor_info` and every process's
  `PROC_PIDTASKINFO` once a second in a detached task, then publishes on the main actor.
- **The core count is read at runtime.** Nothing hardcodes it; the layout derives from the sample.
- **The look is constants, not settings.** Colors live in `MeterImage`, geometry in `MeterLayout`.

## Drawing

Cells sit in two rows; core 0 is the top of the first column and core 1 the bottom. Each cell fills
left to right: user time (nice included) in red, then system time in yellow, over a faint track.

## Process list

- `proc_pidinfo` reports CPU time in Mach absolute units, so the sampler times each tick with
  `mach_absolute_time` and the ratio needs no timebase conversion.
- 100% is one core busy for the whole interval, as in Activity Monitor.
- A process with no earlier sample waits one tick, so the menu reads "Measuring…" for the first second.
- A click quits: an app through `NSRunningApplication.terminate()`, anything else with `SIGTERM`.
  Holding Option swaps every row for its alternate, Force Quit (`forceTerminate()` or `SIGKILL`).
- Rows for processes another user owns are shown but disabled; the menu never asks for admin rights.
