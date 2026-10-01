#!/usr/bin/env python3
"""Development-only auto Hot Reload / Hot Restart driver for LT.

This is a *dev tool*, not part of the product. It is never imported by the
Flutter application, is not declared in ``pubspec.yaml`` and therefore cannot
end up in a release build. See ``docs/development/hot-reload.md``.

What it does
------------
* starts a single ``flutter run`` child process, attached to a pseudo terminal
  so the interactive ``r`` / ``R`` / ``q`` commands keep working;
* polls the project tree (stdlib only, no third-party watcher required);
* debounces bursts of edits into a single action;
* classifies each change and coalesces to the highest required action:
  ``HOT_RELOAD < HOT_RESTART < FULL_RESTART``;
* runs ``flutter gen-l10n`` for ARB edits and ``flutter pub get`` for
  ``pubspec.yaml`` before reloading/restarting.

Only the standard library is used.
"""

from __future__ import annotations

import argparse
import errno
import os
import queue
import select
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from enum import IntEnum
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

# ---------------------------------------------------------------------------
# Change policy (pure logic, unit-tested)
# ---------------------------------------------------------------------------

#: Directories (relative to the project root) that must never trigger a reload.
IGNORED_PREFIXES: Tuple[str, ...] = (
    "build/",
    ".dart_tool/",
    ".git/",
    ".idea/",
    ".codebuddy/",
    ".agents/",
    "coverage/",
    "linux/flutter/ephemeral/",
    "windows/flutter/ephemeral/",
    "macos/Flutter/ephemeral/",
    "ios/Flutter/ephemeral/",
    # Flutter-tooling generated registrants: rewritten by build / pub get,
    # never hand-edited, and would otherwise raise a false "full restart".
    "linux/flutter/generated_",
    "windows/flutter/generated_",
    "macos/Flutter/GeneratedPluginRegistrant.",
    "ios/Runner/GeneratedPluginRegistrant.",
    "android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.",
    # gen-l10n output: reacting to it would create an ARB -> reload loop.
    "lib/l10n/generated/",
)

IGNORED_SUFFIXES: Tuple[str, ...] = (
    ".pyc",
    ".log",
    ".swp",
    ".tmp",
    ".orig",
    ".rej",
    "~",
    ".lock",  # pubspec.lock is written by `flutter pub get`
)

IGNORED_NAMES: Tuple[str, ...] = (
    ".flutter-plugins",
    ".flutter-plugins-dependencies",
)

#: Native/build roots. A change here can never be applied by a hot reload.
NATIVE_ROOTS: Tuple[str, ...] = (
    "linux/",
    "android/",
    "macos/",
    "windows/",
    "ios/",
)


class ChangeKind(IntEnum):
    """What a changed file *is*, independent of the action it requires."""

    DART = 0
    ASSET = 1
    ARB = 2
    PUBSPEC = 3
    NATIVE = 4


class Action(IntEnum):
    """Required response. The integer value *is* the severity ordering."""

    NONE = 0
    HOT_RELOAD = 1
    HOT_RESTART = 2
    FULL_RESTART = 3


@dataclass(frozen=True)
class Change:
    """A single changed file, expressed relative to the project root."""

    path: str
    kind: ChangeKind


def normalize(path: str) -> str:
    """Return a repo-relative, forward-slash path for classification."""
    rel = path.replace(os.sep, "/")
    while rel.startswith("./"):
        rel = rel[2:]
    return rel.lstrip("/")


def is_ignored(path: str) -> bool:
    """True when a path must never be watched (build output, generated, VCS)."""
    rel = normalize(path)
    if not rel:
        return True
    for prefix in IGNORED_PREFIXES:
        if rel.startswith(prefix):
            return True
    base = rel.rsplit("/", 1)[-1]
    if base in IGNORED_NAMES:
        return True
    if base.startswith("."):
        return True
    for suffix in IGNORED_SUFFIXES:
        if base.endswith(suffix):
            return True
    return False


def classify_path(path: str) -> Optional[ChangeKind]:
    """Map a path to its :class:`ChangeKind`, or ``None`` if not watched."""
    rel = normalize(path)
    if is_ignored(rel):
        return None

    base = rel.rsplit("/", 1)[-1]
    if rel == "pubspec.yaml":
        return ChangeKind.PUBSPEC
    if rel.startswith("lib/") and base.endswith(".arb"):
        return ChangeKind.ARB
    if rel.startswith("assets/"):
        return ChangeKind.ASSET
    if rel.startswith("lib/") and base.endswith(".dart"):
        return ChangeKind.DART
    for root in NATIVE_ROOTS:
        if rel.startswith(root):
            return ChangeKind.NATIVE
    return None


#: Default response for every kind. ARB/PUBSPEC additionally run a pre-step.
#
# ARB maps to HOT_RESTART rather than HOT_RELOAD: hot-reloading the regenerated
# ``app_localizations_*`` libraries was observed to drop the device connection
# ("Lost connection to device") on Linux desktop, while a restart is stable.
# The tool still runs ``gen-l10n`` itself first.
_KIND_ACTION: Dict[ChangeKind, Action] = {
    ChangeKind.DART: Action.HOT_RELOAD,
    ChangeKind.ASSET: Action.HOT_RESTART,
    ChangeKind.ARB: Action.HOT_RESTART,
    ChangeKind.PUBSPEC: Action.HOT_RESTART,
    ChangeKind.NATIVE: Action.FULL_RESTART,
}

_KIND_LABEL: Dict[ChangeKind, str] = {
    ChangeKind.DART: "Dart",
    ChangeKind.ASSET: "asset",
    ChangeKind.ARB: "l10n",
    ChangeKind.PUBSPEC: "pubspec",
    ChangeKind.NATIVE: "native",
}


@dataclass
class Plan:
    """The coalesced response to one debounce window."""

    action: Action = Action.NONE
    gen_l10n: bool = False
    pub_get: bool = False
    changes: List[Change] = field(default_factory=list)

    @property
    def is_empty(self) -> bool:
        return not self.changes

    def summary(self) -> str:
        """One-line description of the changes, e.g. ``3 Dart files``."""
        counts: Dict[ChangeKind, int] = {}
        for change in self.changes:
            counts[change.kind] = counts.get(change.kind, 0) + 1
        parts = []
        for kind in (ChangeKind.DART, ChangeKind.ASSET, ChangeKind.ARB,
                     ChangeKind.PUBSPEC, ChangeKind.NATIVE):
            n = counts.get(kind, 0)
            if not n:
                continue
            label = _KIND_LABEL[kind]
            parts.append(f"{n} {label} file" + ("" if n == 1 else "s"))
        return ", ".join(parts) if parts else "no changes"


def plan_for(changes: Iterable[Change]) -> Plan:
    """Coalesce a set of changes into the single highest-severity action."""
    plan = Plan()
    for change in changes:
        plan.changes.append(change)
        action = _KIND_ACTION[change.kind]
        if action > plan.action:
            plan.action = action
        if change.kind is ChangeKind.ARB:
            plan.gen_l10n = True
        elif change.kind is ChangeKind.PUBSPEC:
            plan.pub_get = True
    return plan


class Debouncer:
    """Collects changes and reports readiness once the tree goes quiet."""

    def __init__(self, delay_seconds: float) -> None:
        self._delay = delay_seconds
        self._pending: List[Change] = []
        self._last_change: Optional[float] = None

    def add(self, changes: Sequence[Change], now: float) -> None:
        if not changes:
            return
        self._pending.extend(changes)
        self._last_change = now

    @property
    def pending_count(self) -> int:
        return len(self._pending)

    def ready(self, now: float) -> bool:
        if not self._pending or self._last_change is None:
            return False
        return (now - self._last_change) >= self._delay

    def take(self) -> List[Change]:
        changes, self._pending, self._last_change = self._pending, [], None
        return changes


# ---------------------------------------------------------------------------
# File watching (stdlib polling; ~500 project files, cheap and portable)
# ---------------------------------------------------------------------------

Snapshot = Dict[str, Tuple[int, int]]


class FileWatcher:
    """Polls the watch roots and yields changes since the previous scan."""

    def __init__(self, root: Path, watch_roots: Sequence[str]) -> None:
        self._root = root
        self._roots = list(watch_roots)
        self._snapshot: Snapshot = {}

    def _iter_files(self) -> Iterable[str]:
        for entry in self._roots:
            target = self._root / entry
            if target.is_file():
                yield entry
            elif target.is_dir():
                for dirpath, dirnames, filenames in os.walk(target):
                    rel_dir = normalize(str(Path(dirpath).relative_to(self._root)))
                    if rel_dir == ".":
                        rel_dir = ""
                    dirnames[:] = [
                        d for d in dirnames
                        if not is_ignored(f"{rel_dir}/{d}/" if rel_dir else f"{d}/")
                    ]
                    for name in filenames:
                        yield f"{rel_dir}/{name}" if rel_dir else name

    def scan(self) -> Snapshot:
        result: Snapshot = {}
        for rel in self._iter_files():
            if is_ignored(rel):
                continue
            try:
                st = os.stat(self._root / rel)
            except OSError:
                continue
            result[rel] = (st.st_mtime_ns, st.st_size)
        return result

    def prime(self) -> None:
        """Record the current tree without reporting anything as changed."""
        self._snapshot = self.scan()

    def poll(self) -> List[Change]:
        """Return changes since the last poll and update the snapshot."""
        current = self.scan()
        changes: List[Change] = []
        for rel, meta in current.items():
            if self._snapshot.get(rel) != meta:
                kind = classify_path(rel)
                if kind is not None:
                    changes.append(Change(path=rel, kind=kind))
        self._snapshot = current
        return changes


# ---------------------------------------------------------------------------
# Flutter process control (PTY so interactive r / R / q work)
# ---------------------------------------------------------------------------

#: Output markers used to detect runtime state. Matched case-insensitively.
_READY_MARKERS = (
    "flutter run key commands",
    "a dart vm service on linux is available at",
    "a dart vm service",
    "debug service listening on",
    "is available at:",
)
_RELOAD_OK_MARKERS = (
    "reloaded",
    "reloaded 1 of",
    "restarted application",
)
_RELOAD_FAIL_MARKERS = (
    "failed to reload",
    "reload failed",
    "hot reload was rejected",
    "could not reload",
    "not supported for hot reload",
    "compilation failed",
    "recompile failed",
)
_RESTART_FAIL_MARKERS = (
    "restart failed",
    "failed to restart",
)


class FlutterSession:
    """Owns the ``flutter run`` child process and its pseudo terminal."""

    def __init__(self, command: Sequence[str], cwd: Path) -> None:
        self._command = list(command)
        self._cwd = cwd
        self._proc: Optional[subprocess.Popen] = None
        self._master_fd: Optional[int] = None
        self.events: "queue.Queue[str]" = queue.Queue()
        self.ready = False
        self.exited = False
        self._reader: Optional[threading.Thread] = None

    # -- lifecycle ---------------------------------------------------------

    def start(self) -> None:
        import pty  # Linux/macOS only; this tool targets Linux desktop.

        master_fd, slave_fd = pty.openpty()
        self._proc = subprocess.Popen(
            self._command,
            cwd=str(self._cwd),
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
            preexec_fn=os.setsid,
        )
        os.close(slave_fd)
        self._master_fd = master_fd
        self._reader = threading.Thread(target=self._pump, daemon=True)
        self._reader.start()

    def is_running(self) -> bool:
        return self._proc is not None and self._proc.poll() is None

    def send(self, command: str) -> None:
        """Send a Flutter interactive command (``r``, ``R``, ``q``, …)."""
        if self._master_fd is None:
            return
        try:
            os.write(self._master_fd, command.encode())
        except OSError:
            pass

    def terminate(self) -> None:
        if self._proc is None or self._proc.poll() is not None:
            return
        try:
            self.send("q")  # ask Flutter to shut down cleanly first
            self._proc.wait(timeout=5)
        except (subprocess.TimeoutExpired, OSError):
            try:
                os.killpg(os.getpgid(self._proc.pid), signal.SIGTERM)
                self._proc.wait(timeout=5)
            except (subprocess.TimeoutExpired, ProcessLookupError, OSError):
                try:
                    os.killpg(os.getpgid(self._proc.pid), signal.SIGKILL)
                except (ProcessLookupError, OSError):
                    pass
        if self._master_fd is not None:
            try:
                os.close(self._master_fd)
            except OSError:
                pass
            self._master_fd = None

    # -- output pump -------------------------------------------------------

    def _pump(self) -> None:
        assert self._master_fd is not None
        buffer = b""
        while True:
            try:
                ready, _, _ = select.select([self._master_fd], [], [], 0.2)
            except (OSError, ValueError):
                break
            if self._master_fd in ready:
                try:
                    chunk = os.read(self._master_fd, 4096)
                except OSError as exc:
                    if exc.errno == errno.EIO:  # child closed the PTY
                        break
                    break
                if not chunk:
                    break
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    self._handle_line(line)
                self._write_stdout(chunk)
            if self._proc is not None and self._proc.poll() is not None:
                # Drain whatever is left before declaring the session over.
                try:
                    while True:
                        chunk = os.read(self._master_fd, 4096)
                        if not chunk:
                            break
                        self._write_stdout(chunk)
                except OSError:
                    pass
                break
        if buffer:
            self._handle_line(buffer)
        self.exited = True

    @staticmethod
    def _write_stdout(chunk: bytes) -> None:
        try:
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
        except (BrokenPipeError, ValueError):
            pass

    def _handle_line(self, raw: bytes) -> None:
        line = raw.decode("utf-8", errors="replace").strip()
        if not line:
            return
        low = line.lower()
        if not self.ready and any(m in low for m in _READY_MARKERS):
            self.ready = True
            self.events.put("ready")
            return
        if any(m in low for m in _RESTART_FAIL_MARKERS):
            self.events.put("restart_failed")
            return
        if any(m in low for m in _RELOAD_FAIL_MARKERS):
            self.events.put("reload_failed")
            return
        if any(m in low for m in _RELOAD_OK_MARKERS):
            self.events.put("reload_ok")


# ---------------------------------------------------------------------------
# Keyboard control
# ---------------------------------------------------------------------------

class KeyReader:
    """Reads raw key presses and forwards them to Flutter.

    ``p`` is intercepted to toggle auto reload; everything else (``r``, ``R``,
    ``q``, ``h`` …) is passed straight through so the native Flutter shortcuts
    keep working.
    """

    def __init__(self, session: FlutterSession, state: "RunState") -> None:
        self._session = session
        self._state = state
        self._fd = sys.stdin.fileno() if sys.stdin.isatty() else None
        self._saved = None
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        if self._fd is None:
            return
        import termios
        import tty

        self._saved = termios.tcgetattr(self._fd)
        tty.setcbreak(self._fd)
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        if self._fd is not None and self._saved is not None:
            import termios

            try:
                termios.tcsetattr(self._fd, termios.TCSADRAIN, self._saved)
            except termios.error:
                pass
            self._saved = None

    def _loop(self) -> None:
        assert self._fd is not None
        while not self._state.stopping:
            try:
                ready, _, _ = select.select([self._fd], [], [], 0.2)
            except (OSError, ValueError):
                break
            if self._fd not in ready:
                continue
            try:
                data = os.read(self._fd, 32)
            except OSError:
                break
            if not data:
                break
            text = data.decode("utf-8", errors="ignore")
            for char in text:
                if char == "p":
                    self._state.toggle_pause()
                else:
                    self._session.send(char)


@dataclass
class RunState:
    auto_paused: bool = False
    stopping: bool = False
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def toggle_pause(self) -> None:
        with self._lock:
            self.auto_paused = not self.auto_paused
            paused = self.auto_paused
        log("auto", f"Auto reload: {'PAUSED' if paused else 'ON'}")


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

EXIT_OK = 0
EXIT_ERROR = 1


def log(tag: str, message: str) -> None:
    """Single, quiet, emoji-free log line."""
    sys.stdout.write(f"[{tag}] {message}\n")
    sys.stdout.flush()


def build_flutter_command(flutter: str, device: str,
                          extra: Sequence[str]) -> List[str]:
    return [flutter, "run", "-d", device, *extra]


def find_bundle_assets(root: Path) -> Optional[Path]:
    """Locate the running desktop bundle's ``flutter_assets`` directory."""
    base = root / "build" / "linux"
    if not base.is_dir():
        return None
    for candidate in base.glob("*/*/bundle/data/flutter_assets"):
        if candidate.is_dir():
            return candidate
    return None


def sync_assets(root: Path, changes: Sequence[Change]) -> bool:
    """Copy changed assets into the live bundle so a restart picks them up.

    Desktop Flutter reads assets from the built bundle, not from the source
    tree, so a restart alone would not refresh them.
    """
    bundle = find_bundle_assets(root)
    if bundle is None:
        return False
    copied = 0
    for change in changes:
        if change.kind is not ChangeKind.ASSET:
            continue
        source = root / change.path
        target = bundle / change.path
        if not source.is_file():
            continue
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
            copied += 1
        except OSError:
            return False
    return copied > 0


def run_prestep(command: Sequence[str], cwd: Path, label: str) -> bool:
    """Run a helper command (gen-l10n / pub get); report success."""
    log(label, " ".join(str(c) for c in command[1:]))
    try:
        result = subprocess.run(
            list(command), cwd=str(cwd), capture_output=True, text=True,
        )
    except OSError as exc:
        log(label, f"failed to start: {exc}")
        return False
    if result.returncode != 0:
        output = (result.stderr or result.stdout or "").strip()
        log(label, f"failed (exit {result.returncode})")
        if output:
            sys.stdout.write(output + "\n")
        sys.stdout.flush()
        return False
    return True


class DevHotReload:
    """Wires the watcher, the debouncer and the Flutter session together."""

    def __init__(self, options: argparse.Namespace) -> None:
        self.root = Path(options.root).resolve()
        self.flutter = options.flutter
        self.device = options.device
        self.extra_args = list(options.extra)
        self.debounce = options.debounce / 1000.0
        self.poll = options.poll / 1000.0
        self.watch_roots = list(options.watch)
        self._state = RunState()
        self._session: Optional[FlutterSession] = None
        self._keys: Optional[KeyReader] = None
        self._debouncer = Debouncer(self.debounce)
        self._last_request: Tuple[str, float] = ("", 0.0)

    # -- setup -------------------------------------------------------------

    def _install_signals(self) -> None:
        def handler(_signum, _frame):
            self._state.stopping = True

        signal.signal(signal.SIGINT, handler)
        signal.signal(signal.SIGTERM, handler)

    # -- main loop ---------------------------------------------------------

    def run(self) -> int:
        command = build_flutter_command(self.flutter, self.device,
                                        self.extra_args)
        log("LT dev", f"Starting Flutter on {self.device}...")
        log("LT dev", " ".join(command))

        if not self._preflight():
            return EXIT_ERROR

        session = FlutterSession(command, self.root)
        try:
            session.start()
        except OSError as exc:
            log("LT dev", f"failed to launch flutter: {exc}")
            return EXIT_ERROR
        self._session = session

        for root in self.watch_roots:
            log("watch", f"{root.rstrip('/')}/")
        log("LT dev", "auto reload ready; p pauses, q quits")

        self._keys = KeyReader(session, self._state)
        self._keys.start()
        self._install_signals()

        watcher = FileWatcher(self.root, self.watch_roots)
        watcher.prime()

        try:
            self._loop(session, watcher)
        finally:
            self._shutdown(session)
        return EXIT_OK

    def _preflight(self) -> bool:
        try:
            result = subprocess.run(
                [self.flutter, "--version"],
                capture_output=True, text=True, timeout=120,
            )
        except FileNotFoundError:
            log("LT dev", f"'{self.flutter}' was not found on PATH")
            return False
        except OSError as exc:
            log("LT dev", f"could not run '{self.flutter}': {exc}")
            return False
        if result.returncode != 0:
            log("LT dev", f"'{self.flutter} --version' failed")
            return False
        return True

    def _loop(self, session: FlutterSession, watcher: FileWatcher) -> None:
        while not self._state.stopping and session.is_running():
            time.sleep(self.poll)
            now = time.monotonic()
            changes = watcher.poll()
            if changes and not self._state.auto_paused:
                self._debouncer.add(changes, now)
            self._drain_events(session)

            if session.ready and not self._state.auto_paused:
                if self._debouncer.ready(now):
                    pending = self._debouncer.take()
                    self._execute(plan_for(pending), session)

        if session.exited and not self._state.stopping:
            log("LT dev", "flutter exited")

    def _drain_events(self, session: FlutterSession) -> None:
        while True:
            try:
                event = session.events.get_nowait()
            except queue.Empty:
                return
            if event == "restart_failed":
                log("restart", "Hot restart failed. Full restart required "
                               "(quit and re-run the tool).")
            elif event == "reload_failed":
                action, when = self._last_request
                if action == "reload" and (time.monotonic() - when) < 15:
                    log("reload", "Hot reload failed; attempting hot restart.")
                    self._send(("restart", time.monotonic()), "R", "restart",
                               "Hot restart", session)

    # -- actions -----------------------------------------------------------

    def _send(self, request: Tuple[str, float], command: str, tag: str,
              label: str, session: FlutterSession) -> None:
        self._last_request = request
        log(tag, label)
        session.send(command)

    def _execute(self, plan: Plan, session: FlutterSession) -> None:
        if plan.is_empty:
            return
        log("change", plan.summary())

        if plan.gen_l10n:
            if not run_prestep([self.flutter, "gen-l10n"], self.root, "l10n"):
                log("l10n", "gen-l10n failed; skipping reload")
                return
        if plan.pub_get:
            if not run_prestep([self.flutter, "pub", "get"], self.root, "pub"):
                log("pub", "pub get failed; skipping restart")
                return
            log("pub", "note: new plugins/native deps need a full restart")

        if plan.action is Action.FULL_RESTART:
            log("restart", "Full restart required (native/build change). "
                           "Quit (q) and re-run the tool.")
            return
        if plan.action is Action.HOT_RESTART:
            if plan.changes and any(c.kind is ChangeKind.ASSET
                                    for c in plan.changes):
                if not sync_assets(self.root, plan.changes):
                    log("asset", "could not refresh bundle assets; a full "
                                 "restart may be required for asset changes")
            self._send(("restart", time.monotonic()), "R", "restart",
                       "Hot restart", session)
            return
        if plan.action is Action.HOT_RELOAD:
            self._send(("reload", time.monotonic()), "r", "reload",
                       "Hot reload", session)

    def _shutdown(self, session: FlutterSession) -> None:
        if self._keys is not None:
            self._keys.stop()
        session.terminate()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

DEFAULT_WATCH_ROOTS: Tuple[str, ...] = (
    "lib",
    "assets",
    "pubspec.yaml",
    "linux",
    "android",
    "macos",
    "windows",
    "ios",
)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    """Split our options from the ones forwarded to ``flutter run``."""
    argv = list(argv)
    if "--" in argv:
        split = argv.index("--")
        our_args, flutter_args = argv[:split], argv[split + 1:]
    else:
        our_args, flutter_args = argv, []

    parser = argparse.ArgumentParser(
        prog="dev_hot_reload.py",
        description="Auto Hot Reload / Hot Restart for LT on Linux desktop.",
    )
    parser.add_argument("--device", "-d", default="linux",
                        help="Flutter device id (default: linux)")
    parser.add_argument("--flutter", default="flutter",
                        help="Path to the flutter executable")
    parser.add_argument("--root", default=".",
                        help="Project root (default: current directory)")
    parser.add_argument("--debounce", type=int, default=500,
                        help="Quiet window before reloading, in ms (default 500)")
    parser.add_argument("--poll", type=int, default=400,
                        help="File scan interval, in ms (default 400)")
    parser.add_argument("--watch", action="append", default=None,
                        help="Watch root, repeatable (defaults to lib, assets, "
                             "pubspec.yaml, native dirs)")
    options = parser.parse_args(our_args)
    options.extra = flutter_args
    if options.watch is None:
        options.watch = list(DEFAULT_WATCH_ROOTS)
    return options


def main(argv: Optional[Sequence[str]] = None) -> int:
    options = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        return DevHotReload(options).run()
    except KeyboardInterrupt:
        return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
