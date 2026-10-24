<img src="docs/images/app-icon.png" width="88" height="88" alt="PluginShelf">

# PluginShelf

A native macOS audio plug-in manager. Find plug-ins quickly, back them up in batches, and restore or remove them from one place.

[Download 1.1 (build 15)](https://github.com/xincheng1237/PluginShelf/releases/latest) · [简体中文](README.md) · [Release notes](CHANGELOG.en.md) · [Report an issue](https://github.com/xincheng1237/PluginShelf/issues)

![PluginShelf plug-in library](docs/screenshots/01-插件管理与时间筛选.png)

## Features

- **Find plug-ins:** scan AU, VST2, VST3, AAX, CLAP, LV2, RTAS and other supported locations, with search, date filters, sorting and alphabet navigation.
- **Back up and restore in batches:** export plug-in files with a checksum manifest and restore them to their original locations.
- **Manage deleted plug-ins:** review the selection and complete two-step confirmation before deletion, then view records, restore items or permanently delete them in the app.
- **Feel at home on macOS:** native windows, toolbars and multiple selection, with English and Simplified Chinese interfaces that follow the system by default.
- **Check for updates:** occasional checks at launch with a quiet notice when a newer release is available, plus manual checks in the app menu and Settings.

## Install

Requires **macOS 14 or later**. One **Universal 2** download supports both **Apple silicon and Intel**.

1. Download the DMG from [Releases](https://github.com/xincheng1237/PluginShelf/releases/latest).
2. Open it and drag PluginShelf into Applications. Quit the previous version before replacing it.
3. Open PluginShelf from Applications to scan your plug-ins.

The current release is ad-hoc signed and has not been notarized by Apple. See the [installation guide](docs/INSTALLATION.en.md) for first-launch and upgrade details.

If you have an earlier build of 1.1, download and replace it manually from Releases. The existing updater compares version numbers and does not notify you about a higher build of the same version.

## Backups and deletion

Backups contain plug-in files, not separate sample libraries, licenses or vendor installers. Restoring never overwrites an existing file at the destination.

Deleted plug-ins go to the system Trash. Automatic removal follows Finder’s “Remove items from the Trash after 30 days” setting; emptying the Trash removes them sooner. PluginShelf installs no background cleaner or login item.

App-contained AUv3 extensions are view-only. Protected directories may not be writable, and automatic categories do not cover every plug-in; manual categorization is available. The [detailed user guide](docs/USER_GUIDE.md) is currently in Chinese.

## Development and feedback

Built with SwiftUI, AppKit and Swift 6, with no third-party runtime dependencies. See [CONTRIBUTING.md](CONTRIBUTING.md) for build, test and release instructions, and [verification records](docs/VERIFICATION.md) for the tested scope.

Use [Issues](https://github.com/xincheng1237/PluginShelf/issues) for bugs and suggestions. Redact private paths and license information before posting screenshots or logs.

The source is publicly available. No open-source license has been granted at this time.
