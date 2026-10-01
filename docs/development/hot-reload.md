# Development: automatic Hot Reload / Hot Restart

LT ships a small **development-only** driver that watches the project tree and
applies edits to a running Linux desktop app without you going back to the
`flutter run` terminal to press `r`.

It is a dev tool: it lives under `tool/`, is written in Python (standard
library only) and is never referenced by `pubspec.yaml`, `lib/` or any Flutter
build. Release builds contain none of it. It is **not** an over-the-air update
mechanism — it only drives a local `flutter run` session.

## Requirements

- Linux desktop (the tool controls `flutter run` through a PTY).
- `flutter` on `PATH`, with the Linux desktop device available
  (`flutter devices` should list `Linux (desktop)`).
- Python 3.8+ (`python3`). No third-party packages, no `watchexec`/`entr`.

## Start

```bash
python3 tool/dev_hot_reload.py --device linux
```

A thin wrapper is also provided:

```bash
scripts/dev.sh
```

Arguments after `--` are forwarded verbatim to `flutter run`:

```bash
python3 tool/dev_hot_reload.py --device linux -- --dart-define=FOO=bar
```

Useful options:

| Option | Default | Meaning |
| --- | --- | --- |
| `--device`, `-d` | `linux` | Flutter device id |
| `--flutter` | `flutter` | Path to the Flutter executable |
| `--root` | `.` | Project root |
| `--debounce` | `500` | Quiet window (ms) before acting |
| `--poll` | `400` | File scan interval (ms) |
| `--watch` | see below | Watch root (repeatable) |

Default watch roots: `lib`, `assets`, `pubspec.yaml`, and the native
directories (`linux`, `android`, `macos`, `windows`, `ios`).

## What happens on a change

The tool coalesces a burst of edits within the debounce window into a **single**
action, choosing the highest severity required:

```
HOT_RELOAD  <  HOT_RESTART  <  FULL_RESTART
```

| Change | Pre-step | Action |
| --- | --- | --- |
| `lib/**/*.dart` | — | Hot Reload (`r`) |
| `assets/**` (e.g. `assets/icons/*.svg`) | copy into the running bundle | Hot Restart (`R`) |
| `lib/l10n/*.arb` | `flutter gen-l10n` | Hot Restart (`R`) |
| `pubspec.yaml` | `flutter pub get` | Hot Restart (`R`) |
| `linux/`, `android/`, `macos/`, `windows/`, `ios/` | — | Full restart required (prompt only) |

Notes:

- **SVG / assets.** Desktop Flutter reads assets from the built bundle, not the
  source tree, so a plain reload would not refresh them. The tool copies changed
  assets into the live `flutter_assets` directory and then hot-restarts.
- **ARB.** The tool runs `gen-l10n` itself and then hot-restarts. Hot-reloading
  the regenerated localization libraries was measured to drop the device
  connection on Linux desktop, so a restart is used. Generated output under
  `lib/l10n/generated/` is permanently ignored, so `ARB → gen-l10n → generated
  Dart → reload → …` cannot loop.
- **pubspec / plugins.** `pub get` runs first; a hot restart follows. If the
  change pulls in a new plugin or native dependency, a full restart (quit and
  re-run) is still required — the tool prints a reminder.
- Nothing is reloaded while the burst is still in flight; e.g. `dart + pubspec`
  in one window produces exactly one hot restart, never `r` then `R`.

Ignored paths: `build/`, `.dart_tool/`, `.git/`, `.idea/`, `coverage/`,
`linux/flutter/ephemeral/`, `lib/l10n/generated/`, `pubspec.lock`, log/swap/temp
files, and dotfiles. These never trigger a reload.

## Keyboard controls

The tool keeps Flutter's own interactive commands working while auto reload is
on:

| Key | Action |
| --- | --- |
| `r` | manual hot reload |
| `R` | manual hot restart |
| `p` | toggle auto reload (`Auto reload: ON / PAUSED`) |
| `q` | quit |
| `h` | help (passed through to Flutter) |

`p` is useful when an agent is rewriting many files and you do not want a
half-finished state reloaded mid-edit.

## Failure handling

If a hot reload is rejected (compile error), the tool automatically attempts a
hot restart. If that also fails, it reports that a full restart is required
instead of retrying forever.

## Stopping

`q` or `Ctrl+C`. The tool sends a clean quit to Flutter, waits, and only then
escalates to signals, so no `flutter` or LT process is left behind. The terminal
is always restored.

## Troubleshooting

- **`'flutter' was not found on PATH`** — pass `--flutter /path/to/flutter`.
- **window does not open** — make sure `flutter devices` lists
  `Linux (desktop)`; run `flutter doctor` for missing desktop toolchains.
- **`pub get` / `gen-l10n` failed** — the tool reports the failure and skips the
  reload; fix the error and save again.
- **asset change not visible** — the bundle directory could not be located
  (only happens before the first build). Restart the tool once.
