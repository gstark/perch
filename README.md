# Perch

> [!IMPORTANT]
> Perch is a personal fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar.
> It is not the official Tinycast app and is not affiliated with the Tinycast project. Perch has
> no support. For the full app, use Tinycast.

A personal macOS menu-bar app: a fuzzy app launcher, global hotkeys, clipboard history, an inline
calculator with unit conversion, an emoji picker, window management, a per-core CPU meter with
AI-written labels for busy processes, a panel for a Proxmox host's CPU use, and a menu bar warning
for git commits that are not pushed.

## Relation to Tinycast

Perch started from Tinycast at upstream commit `c048b316` on 2026-10-05. It removes most of
Tinycast's features and adds new ones. The CPU meter replaces
[MenuMeters](https://github.com/emcrisostomo/MenuMeters) and is new code. [PLAN.md](PLAN.md)
records what was kept and why. [NOTICE.md](NOTICE.md) records the attribution.

Upstream fixes can still apply to Perch. The source folder and many type names still say Tinycast,
so upstream commits cherry-pick onto the same paths.

## No support

Perch is built for one person and one Mac. The code is public because the licence requires it and
because someone may find it useful to read.

- The releases and the Homebrew cask are for my own Macs. They are signed but not notarized.
- Issues, pull requests, feature requests and security reports are not accepted.
- Do not report a Perch problem to Tinycast. Perch changes too much of the code for an upstream
  report to be useful.
- Behaviour, settings and data formats can change or break at any time, without notice.

You can fork Perch under the terms of its licence. If you do, the fork is yours to maintain.

## Installing

Perch needs macOS 26 or later on Apple silicon.

```bash
brew install gstark/tap/perch
```

## Building

Building needs Xcode 26. Run `just install` to build and install the app. Run `just homebrew` to
publish a release and update the cask.
[docs/development.md](docs/development.md) covers the toolchain and every other recipe.

## Licence

Perch is licensed under the GNU Affero General Public License v3, the same as Tinycast. See
[LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

Perch comes with no warranty, to the extent the law permits. Sections 15 and 16 of the licence
state the full disclaimer.
