# Changelog

All notable changes to yast-on-arch. Versions follow [semantic versioning](https://semver.org/).

## 0.3.1 — 2026-10-26

### Changed

- **Each "More - System - …" section has a colour of its own** in the Control Center, instead of
  all of them sharing the Utilities grey. Categories that match a genre use its colour
  (Networking → Network, Security & Accounts → Security, Hardware & Drivers → Hardware, Gaming
  Helpers → Games, System Info & Monitors → Information, Other → Utilities); the other 14 have
  hand-picked colours that are easy to tell apart.

### New

- **`[Aliases]` in `~/.config/yast-on-arch/section-colors.ini`**: `Section name=Genre` puts any
  section into another genre's colour, added to the built-in aliases or replacing one. Before,
  which section belonged to which genre was fixed in the program. A single section can still be
  given its own colour with its full name under `[Colors]`. See the User Guide, section 4.

yast-on-arch changes are Copyright (C) 2026 by Eugene Flanagin. Licensed under the GNU General Public License v2.0 (GPL-2.0), like YaST itself.

## 0.3.0 — 2026-10-26

### New

- **Colour-coded Control Center.** A *Section colours* box under the search field: **Off**,
  **Headers** (coloured section headers and a matching stripe in the group list; the default) or
  **Whole block** (the whole section, programs included, is tinted). Related sections share a
  colour ("Graphics - …" pink, "Games - …" green, Hardware orange…). Saved in
  `~/.config/yast-on-arch/section-colors.ini`, where every colour can be changed. A new genre gets
  the colour furthest from the ones in use; a renamed section keeps its colour.
- **"Add or change..." in the Control Center**: a window to add a program, add a section (pick a
  genre to share its colour, or type a new one), move a program to another section and rename a
  section. Also on a program's right-click menu. The Control Center restarts by itself afterwards.
- **Move any program and rename any section**, YaST's own included: `yast move-app NAME --to ID`,
  `yast rename-section ID --to NAME` (`--reset` undoes either), `yast list-layout`. Nothing
  installed is changed: the layout is `~/.local/share/yast-on-arch/layout.ini` and survives
  rebuilds. Shown by the Qt Control Center.
- **`yast add-section --name NAME [--genre GENRE] [--icon ICON]`** makes an empty section.
- **User Guide PDF** (`docs/YaST-on-Arch-User-Guide.pdf`, built by `docs/build-pdf.sh`), with
  screenshots of the new features.
- Releases now also carry the User Guide PDF and the patches on their own.

- **Continuous integration** (`.github/workflows/ci.yml`): every push and pull request to `main`
  runs `bootstrap.sh` from scratch in a clean `archlinux:base-devel` container, as a normal user,
  and fails if a pinned commit cannot be fetched, a patch does not apply or anything does not
  build. Then read-only smoke checks: `yast --version`, the client list, `list-sections`,
  `add-app`/`list-apps`/`remove-app` with a throw-away home folder, `ag_probe --selftest`, missing
  shared libraries, `desktop-file-validate`. No YaST module is ever started. The same script,
  `.github/ci/build-and-smoke.sh`, runs on your own PC in Docker.
- **Releases** (`.github/workflows/release.yml`): pushing a tag `vX.Y.Z` that matches `VERSION`
  runs the full CI and then publishes a GitHub release with the source tarball and `SHA256SUMS`;
  the text comes from this file. A published release is never overwritten.

### Changed

- `yast remove-section` also forgets the section's rename and sends programs moved into it back to
  their own sections.
- Names of programs and sections (`add-app --name`, `--new-section`, `add-section`,
  `rename-section`) can't contain commas, `"` or `\` or start or end with a space any more: the
  Control Center showed such names differently from what was typed.
- The release workflow leaves an already published release alone with a notice instead of failing.

### Fixed

- `bootstrap.sh` now installs `qt5-x11extras` (libyui-qt needs it) and `doxygen` (libstorage-ng's
  build runs it). On a fresh Arch system the build stopped without them; the first CI run found it.

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

### Also fixed

- `bootstrap.sh` only asks pacman for dependencies that aren't already satisfied, so systems with replacement packages (for example `autoconf-git`) no longer stop with "conflicting dependencies".

## 0.1.0 — 2026-10-13 (commit 5a87f65, never tagged)

First release: `bootstrap.sh` and patches 01–21 build upstream libyui and YaST into
`~/libyui-port`; Qt, GTK and ncurses front-ends; the classic Qt Control Center with fast search;
Arch stand-ins for package management (Octopi), the hardware probe and storage; Arch-only
KDE Plasma Settings and Package Cache Cleaner modules.
