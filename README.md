# PureClean

Safe cleaning and live system monitoring for macOS — built by **AWS NextGen IT**.

A native SwiftUI app (macOS 14+) with a full dashboard window, a menu bar
presence, and a hard safety guarantee: **personal files are never touched,
and removals go to the Trash whenever possible.**

## Features

### Smart Scan
Animated live scanner (file counter, byte counter, current path, ETA) across:
system junk, browser caches, logs, crash reports, temporary files, thumbnails,
Xcode derived data & archives, Mail attachment caches, old installers,
app leftovers from uninstalled apps, broken symlinks, and the Trash — plus
system insights (storage, memory pressure, CPU load, login items, old
downloads, battery health).

> Language-file stripping is deliberately **not** offered: removing `.lproj`
> folders breaks app code signatures on modern macOS.

### Accurate storage & Trash
- APFS numbers matching Finder: total, used, strictly free, **purgeable**,
  and available (`volumeAvailableCapacityForImportantUsage`).
- Trash size covers `~/.Trash` **and** per-volume `.Trashes`, updates live
  via a kernel file watcher, previews contents, and empties safely after
  confirmation. Sizes descend into packages (a trashed `.app` counts fully).
- When macOS blocks Trash access, the app shows a Full Disk Access prompt —
  never a fake zero.

### Performance monitor
1-second refresh, all values from native APIs (nothing estimated):
- **CPU** — total/user/system, per-core bars, load average, P/E core layout
- **Memory** — Activity-Monitor-style used/app/wired/compressed/cached,
  swap, and kernel memory-pressure level
- **Disk** — read/write throughput (IOKit block-storage statistics),
  capacity, SMART status
- **Network** — up/down throughput with live chart, interface, IP, Wi-Fi
  SSID/signal/link rate (when authorized)
- **GPU** — utilization and memory from the accelerator driver (when exposed)
- **Battery** — charge, health, cycles, raw capacities (mAh), temperature,
  time remaining
- **Sensors** — fan RPM and CPU/GPU temperatures via the SMC (per-model key
  discovery; shows "not available" honestly on Macs that expose nothing)

### Tools
Large files finder, SHA-256-verified duplicate finder, app uninstaller with
leftover discovery, and login-item manager.

### Menu bar
PureClean keeps running in the menu bar when the window closes: live status
lines, Open, Quick Scan, Free Memory, Trash size, Settings, Quit. The icon
can be hidden in Settings; launch-at-login is available via `SMAppService`.

## Safety model

Every destructive operation passes through `SafetyGuard`:
- deletions are only allowed inside an allow-list of cache/log/temp roots;
- forbidden path components (Documents, Desktop, Pictures, `.git`, `.ssh`…)
  are refused anywhere;
- user-reviewed removals (large files, duplicates, uninstaller, leftovers)
  are always trashed, never hard-deleted.

## Building

```bash
brew install xcodegen
xcodegen generate           # project.yml → PureClean.xcodeproj
open PureClean.xcodeproj    # or:
xcodebuild -project PureClean.xcodeproj -scheme PureClean -configuration Release build
```

### Installer

```bash
./build-dmg.sh              # Release build → dist/PureClean.dmg
```

Produces a branded, Retina drag-to-install DMG (rendered background,
positioned icons, volume icon, UDZO-compressed). `make-icon.swift` and
`make-dmg-background.swift` regenerate all artwork from code.

## Permissions

| Permission | Why | Required? |
|---|---|---|
| Full Disk Access | Measure/empty the Trash, Safari cache, Mail caches | Optional — features degrade honestly |
| Notifications | Low-storage / high-memory-pressure alerts | Optional |
| Automation (Finder) | Only used by `build-dmg.sh` for window layout | Dev only |

© 2026 AWS NextGen IT LTD
