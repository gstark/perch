# Perch

A personal macOS menu-bar app: a fuzzy app launcher, global hotkeys, clipboard history, an inline
calculator with unit conversion, an emoji picker, window management, a per-core CPU meter, and a
panel for a Proxmox host's CPU use.

## A fork of Tinycast

Perch is a personal fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar, cut
down to the features above. The CPU meter replaces [MenuMeters](https://github.com/emcrisostomo/MenuMeters)
and is new code. [PLAN.md](PLAN.md) records what was kept and why.

Perch is built for one person. It has no releases, no Homebrew cask, no Discord, and no support.
Issues, pull requests and security reports are not accepted. For the full app, use Tinycast.

## Building

Perch needs macOS 26 or later and Xcode 26. Run `just install` to build and install the app.
[docs/development.md](docs/development.md) covers the toolchain and every other recipe.

## Licence

Perch is licensed under the GNU Affero General Public License v3, the same as Tinycast. See
[LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
