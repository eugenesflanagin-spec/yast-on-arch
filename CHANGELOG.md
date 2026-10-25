# Changelog

All notable changes to yast-on-arch. Versions follow [semantic versioning](https://semver.org/).

## 0.2.0 — 2026-10-25

### New

- **Add your own programs and sections to the Control Center**: `yast add-app`, with
  `remove-app`, `remove-section`, `list-apps`, `list-sections` and `sync-apps`. No root needed.
  Entries are kept in `~/.local/share/yast-on-arch/applications/` and survive re-running
  `bootstrap.sh`. Inputs are checked, the result is run through `desktop-file-validate`, and
  stock YaST entries are never overwritten.
- `bootstrap.sh` installs extra Control Center sections from `arch/applications/groups/`.
- `yast --version`.
- **User Guide** (`docs/USER-GUIDE.md`): plain-English install, everyday use, safety, every
  option, troubleshooting, uninstall and a glossary. Linked from the README.

### Fixed

- **Patches 01, 02, 03 and 05 are really applied now.** Their file headers were unusable, and
  `bootstrap.sh` skipped them without saying so (03 is the Ruby 3.4 fix).
- **A patch that does not apply stops the build** with a message naming it, instead of being
  skipped silently. `YAST_IGNORE_PATCH_FAILURES=1` continues anyway.
- **Upstream is pinned**: every upstream repository is cloned at the commit the patches were
  made and tested against (34 pins). `YAST_UPSTREAM_UNPINNED=1` takes upstream's current code.
- `bootstrap.sh` stops with a clear message on a leftover, half-finished clone instead of
  building it.
- **`yast -r` works without a terminal** (menu entries, Control Center clicks): it uses
  `sudo -n` when that works, otherwise a `pkexec` password dialog, otherwise a terminal window,
  otherwise a visible error. `YAST_ESCALATE=sudo|pkexec|terminal` forces a method,
  `YAST_DEBUG=1` shows what would run.
- `xorg-xhost` is installed by the build (the launcher needs `xhost` for root Qt/GTK windows)
  and the launcher warns when it is missing.
- `YAST_ALLOW_BOOTLOADER_WRITE=1` is passed through `yast -r` (only when set to exactly `1`),
  so the Boot Loader write guard can be lifted on purpose.
- **Menu entries** use the real launcher path of each installation (no hard-coded home folder)
  and are installed by `bootstrap.sh` into `~/.local/share/applications`; an existing file the
  build did not write is left alone. `YAST_NO_MENU_ENTRIES=1` skips them. The text-mode entry
  opens in your desktop's terminal.
- KDE Plasma Settings and Package Cache Cleaner entries start through the port's launcher.
- `docs/probe-agent.md`: correct file and install paths. The self-test transcript no longer
  shows network card addresses.
- README: what the build really installs, module counts, root escalation, pinning.

## 0.1.0 — 2026-10-13 (commit 5a87f65, never tagged)

First release: `bootstrap.sh` and patches 01–21 build upstream libyui and YaST into
`~/libyui-port`; Qt, GTK and ncurses front-ends; the classic Qt Control Center with fast search;
Arch stand-ins for package management (Octopi), the hardware probe and storage; Arch-only
KDE Plasma Settings and Package Cache Cleaner modules.
