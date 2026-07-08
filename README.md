# PureClean — Safe Mac Cleaner

A modern macOS **menu bar** cleaning app (SwiftUI, macOS 14+) focused exclusively on **safe cleaning**. It can never delete personal files — that guarantee is enforced in code, not just in the UI.

## Open & Run

```bash
open PureClean.xcodeproj
```

Press **⌘R** in Xcode. A ✨ sparkles icon appears in your menu bar — click it to open the app.

> The project file is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. If you add new Swift files outside Xcode, re-run `xcodegen generate`.

## Features

| Tab | What it does |
| --- | --- |
| **Home** | Storage / Memory / CPU rings, battery health & cycles, disk SMART status, cache/trash/temp sizes, **Smart Clean** ("You can safely recover X GB") and **Free Memory** |
| **Clean** | Category-by-category cleaning with live sizes and toggles: user & app cache, browser caches (Safari/Chrome/Edge/Firefox), Xcode DerivedData & Archives, logs, crash reports, temp files, QuickLook thumbnails, Trash, old installers · plus a DNS-flush maintenance action |
| **Tools** | Large Files finder (500 MB / 1 GB / 5 GB, review before trash) · Duplicate finder (SHA-256 verified, always keeps one copy) · App Uninstaller (app + caches + prefs + logs + support files, full review sheet) · Startup items (user LaunchAgents toggle + System Settings deep-link) · Storage Analyzer (donut chart of folder sizes) |
| **Monitor** | Live (1 s) CPU & memory charts, network in/out, disk free, SMART status |
| **Settings** | Scheduled cleaning (daily/weekly/monthly), notification thresholds (storage < 10 %, RAM > 90 %, cache > 5 GB), Full Disk Access explainer, launch at login |

## The Safety Model

Everything destructive flows through **`SafetyGuard`** (`Utilities/SafetyGuard.swift`):

1. **Allow-list, not block-list** — automatic cleaning only ever operates inside explicitly approved roots (`~/Library/Caches`, `~/Library/Logs`, DerivedData, temp, `.Trash`…).
2. **Forbidden components** — any path containing `Documents`, `Desktop`, `Pictures`, `Music`, `Movies`, `.git`, `node_modules`, `.ssh`… is refused outright, wherever it appears.
3. **Trash first** — items are moved to the Trash (restorable) whenever possible; hard deletion is a fallback only for guard-approved cache paths.
4. **Review-based tools** (large files, duplicates, uninstaller) act only on files you explicitly ticked, always via Trash, and the duplicate finder physically cannot remove the last copy of a file.
5. **Every clean requires confirmation** and shows the exact recoverable amount first.

## Permissions & Sandbox Notes

- **App Sandbox is disabled** in this build. A cleaner fundamentally needs to enumerate and remove files in `~/Library/Caches` and friends, which the sandbox forbids. This is the same trade-off every cleaning utility makes (distribute via Developer ID + notarization, not the App Store).
- **Full Disk Access** (optional) — only needed for Safari's cache and some diagnostic logs. The Settings tab explains this and deep-links to System Settings. Nothing is requested at first launch.
- **Admin prompt** — only for `purge` (Free Memory) and the DNS flush; both explain themselves before macOS asks for your password.

## Architecture (MVVM)

```
PureClean/
├── App/            PureCleanApp (MenuBarExtra) · AppState (composition root)
├── Models/         CleanCategory, LargeFile, DuplicateGroup, SystemSnapshot…
├── ViewModels/     DashboardViewModel (presentation-only derivations)
├── Managers/       @Observable domain managers:
│                   SystemStatsManager (CPU/RAM/disk/network/battery, 1 s tick)
│                   CleanerManager · MemoryManager · DiskAnalyzerManager
│                   LargeFileFinder · DuplicateFinder · AppUninstaller
│                   StartupManager · NotificationManager · ScheduleManager
│                   PermissionManager
├── Utilities/      SafetyGuard · ShellRunner · formatters & FileManager helpers
└── Views/          Dashboard / Clean / Tools / Monitor / Settings + Components
```

State uses the modern **`@Observable`** macro (Observation framework) — views track exactly the properties they read; heavy scans run off the main actor via `Task.detached` task groups.

## Future Ideas (scaffolded for)

Battery optimization tips, menu shortcuts, widgets, iCloud-synced settings, AI cleaning recommendations, exportable cleaning reports.

---
© 2026 AWS NextGen IT LTD · Built with SwiftUI
