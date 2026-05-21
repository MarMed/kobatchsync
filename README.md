# KOReader Batch Progress Sync Plugin 🚀

A high-performance, resilient, and beautifully designed batch progress synchronization plugin for **KOReader**. It allows Kobo, Kindle, and Android e-readers to cleanly push and pull progress for your entire library in bulk rather than just one book at a time.

This plugin is designed to be fully compatible with both the official KOReader Sync server and self-hosted instances.

---

## ✨ Features

- 📂 **Bulk Push Progress**: Sync your reading progress for all books in your history with a single tap.
- 📥 **Bulk Pull Progress**: Automatically pulls the latest progress from other devices for both items in your reading history and unopened books in your home directory (making sure you pick up where you left off).
- 🛑 **Interactive Safe Cancellation**: Safely cancel or dismiss the sync operation at any time (via the back key or screen tap) without crashes or hanging.
- ⚡ **UI Throttle Engine**: Processes hundreds of skipped books in microseconds in-memory, updating the progress bar and e-ink screen exactly once per network call.
- 📺 **Flawless E-Ink Rendering**: Built with Kindle/Kobo layout recalculation and dynamic coordinate tracking to completely eliminate screen ghosting, dialog overlapping, or blank boxes.
- 🛡️ **Isolated Sandboxing**: Operates in its own namespace to prevent module caching conflicts with KOReader's default `kosync` plugin.
- 🔍 **Resilient Status Reporting**: Smartly flags un-synced books as `Skipped` instead of `Failed` (handling `404` properly) and automatically calculates missing book MD5 checksums on the fly.

---

## 🛠️ Installation

1. Download the latest packaged release from the [GitHub Releases](https://github.com/MarMed/kobatchsync/releases) page or clone this repository.
2. Transfer or extract the `kobatchsync.koplugin` folder to your KOReader plugins directory:
   - **Kobo**: `/mnt/onboard/.kobo/koreader/plugins/kobatchsync.koplugin/`
   - **Kindle**: `/mnt/us/koreader/plugins/kobatchsync.koplugin/`
   - **Android**: `/sdcard/koreader/plugins/kobatchsync.koplugin/`
3. Restart KOReader. The plugin will automatically register itself in the main menu under **Batch progress sync**.

---

## 🚀 How to Use

1. Ensure you are logged in to your Progress Sync account in KOReader's standard **Progress Sync** settings.
2. Open the main menu, navigate to **Batch progress sync**, and choose your action:
   - **Batch push progress from this device (all books)**
   - **Batch pull progress from other devices (all books)**
3. A progress dialog will appear on screen showing live statistics:
   - `Success / Updated`: Books successfully synced.
   - `Skipped`: Books with no remote/local changes, unopened items with identical progress, or missing records.
   - `Failed`: Sync network failures.
4. **Interactive Cancellation**: If the sync is taking too long or you need to exit, simply tap outside the dialog box or press your device's **Back** button to safely abort mid-sync.

---

## 📋 Technical Details

- **Language**: Lua / KOReader Widget API
- **Rate-Limiting**: Strictly adheres to a standard `0.2s` request throttle to remain respectful to public and self-hosted KOReader servers.
- **Dynamic Layout Engine**: Uses `vertical_group:resetLayout()` and clears `FrameContainer.dimen` cache prior to triggering a `"ui"` e-ink refresh, guaranteeing pixel-perfect updates on all Kindle models.

---

## 🤖 AI Generation & Credits

This plugin was entirely co-engineered, debugged, and optimized in partnership with **Antigravity**, an agentic AI coding assistant developed by the Google DeepMind team, customized precisely to solve specific e-reader synchronization requirements.

---

## 📄 License

This project is licensed under the GPLv3 License - see the [LICENSE](LICENSE) file for details.

