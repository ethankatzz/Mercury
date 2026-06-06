# Mercury

A minimal, local-only typing meter that lives in your menu bar. Chrome over noise. It counts
how you type across the whole system (never *what* you type) and gives you a quick typing test
on demand, right from the ribbon.

## What's new vs. the old build
- **Three-view widget.** A minimal tab strip (`now` · `today` · `stats`) under the live readout
  switches the panel between views, all sharing the same chrome header and big live-WPM number:
  - **now** — mode chips (`15s` · `30s` · `60s` · `25w`), the inline typing test, and a live
    **session graph** that fills in as you type.
  - **today** — goal progress, streak + best, an **hourly rhythm** histogram (the hours you
    actually type), and a 14-week **activity heatmap**.
  - **stats** — personal bests per mode, a burst / PB / accuracy summary, a recent-tests
    sparkline, and your last few results.
  - **fun** — a live "rank" (warming up → ludicrous speed), playful equivalences (novels written
    as a %, pages, tweets, finger mileage), a **WPM-spread histogram**, and a this-week bar chart.
- **Your logo, isolated.** The chrome glyphs drive the menu-bar mark (transparent, reads on
  light + dark bars) and the dock icon — the dock icon is the bare logo on a fully transparent
  background, no plate or squircle. It floats on any wallpaper.
- **Quick typing test** built in. Live WPM / accuracy / timer, per-character coloring, a caret.
  Background tracking pauses during a test so it doesn't double-count.
- **Bespoke monochrome design.** No MonkeyType yellow or animal ranks. Wide-tracked uppercase
  micro-labels, a chrome recording dot, minimal outlined mode-chips, a framed test readout, and a
  liquid-metal gradient on the bars, sparklines, and heatmap.

You never need a separate window — click the menu-bar logo and the whole widget drops down.

## Build
Needs macOS with the Swift toolchain (Xcode or Command Line Tools: `xcode-select --install`).

```bash
./build.sh
open Mercury.app
```

On first launch, enable **Mercury** under **System Settings ▸ Privacy & Security ▸ Input
Monitoring**, then relaunch (a tap can't attach until the permission is granted, and macOS
re-checks after a fresh launch). Because rebuilding changes the app's signature, you may need to
toggle the permission off/on again after each rebuild.

## Using it
- **Left-click** the ribbon logo → open the panel.
- **Right-click** (or ⌃-click) the logo → settings (daily goal, idle timeout, live-WPM toggle,
  dock icon, launch-at-login, resets).
- In the panel: **start/stop** a tracking session, tap a **mode chip** to begin a test, and just
  start typing. `↻` restarts, `return` retries a finished test, `esc` closes the panel.

## Privacy
Everything is local. Mercury records keystroke **counts and timing only** — never characters,
words, or which apps you're in. Data lives in
`~/Library/Application Support/Mercury/stats.json`. Delete it to wipe everything.

## Files
- `Theme.swift` — palette, fonts, formatting, asset loading
- `Store.swift` — persisted models, day-keys, streak math
- `StatsEngine.swift` — thread-safe tracking + daily/test aggregation
- `KeystrokeMonitor.swift` — `CGEventTap` listener (counts only)
- `Widgets.swift` — sparkline + progress bar
- `TypingTest.swift` — test engine + focusable rendering view
- `RibbonPanel.swift` — the anchored panel UI
- `AppDelegate.swift` — status item, dock icon, permissions, settings
- `tools/make_icons.py` — regenerates the ribbon/dock art from a source logo

## Renaming
The display name is set in `build.sh` (`CFBundleName`) and a couple of strings in
`AppDelegate.swift` / `RibbonPanel.swift`. The logo is wired by filename, so it stays regardless
of what you call the app.
