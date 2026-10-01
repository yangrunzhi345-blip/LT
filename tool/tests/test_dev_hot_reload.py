#!/usr/bin/env python3
"""Unit tests for the LT dev auto hot-reload tool (stdlib unittest).

Run with::

    python3 -m unittest discover -s tool/tests -v
"""

from __future__ import annotations

import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import dev_hot_reload as hr  # noqa: E402


class IgnoreRuleTests(unittest.TestCase):
    def test_build_and_tooling_outputs_ignored(self) -> None:
        ignored = [
            "build/linux/x64/debug/bundle/data/flutter_assets/assets/x.svg",
            ".dart_tool/package_config.json",
            ".git/HEAD",
            "coverage/lcov.info",
            "linux/flutter/ephemeral/.plugin_symlinks/x",
            "linux/flutter/ephemeral/generated_config.cmake",
            "macos/Flutter/ephemeral/Packages/Generated/Package.swift",
            "ios/Flutter/ephemeral/Packages/Generated/Package.swift",
            "windows/flutter/ephemeral/generated_config.cmake",
            ".idea/workspace.xml",
            "lib/l10n/generated/app_localizations_en.dart",
            "pubspec.lock",
            "some/file.log",
            "some/file.swp",
            "tool/dev_hot_reload.pyc",
            ".flutter-plugins-dependencies",
            ".hidden_file",
            "linux/flutter/generated_plugins.cmake",
            "linux/flutter/generated_plugin_registrant.cc",
            "windows/flutter/generated_plugins.cmake",
            "macos/Flutter/GeneratedPluginRegistrant.swift",
            "android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
        ]
        for path in ignored:
            with self.subTest(path=path):
                self.assertTrue(hr.is_ignored(path))

    def test_source_files_are_watched(self) -> None:
        watched = [
            "lib/main.dart",
            "lib/l10n/app_en.arb",
            "assets/icons/state.svg",
            "pubspec.yaml",
            "linux/runner/main.cc",
        ]
        for path in watched:
            with self.subTest(path=path):
                self.assertFalse(hr.is_ignored(path))


class ClassifyTests(unittest.TestCase):
    def test_dart_source(self) -> None:
        self.assertIs(hr.classify_path("lib/main.dart"), hr.ChangeKind.DART)
        self.assertIs(hr.classify_path("lib/features/x/y.dart"),
                      hr.ChangeKind.DART)

    def test_svg_asset(self) -> None:
        self.assertIs(hr.classify_path("assets/icons/state.svg"),
                      hr.ChangeKind.ASSET)
        self.assertIs(hr.classify_path("assets/cover.png"),
                      hr.ChangeKind.ASSET)

    def test_arb(self) -> None:
        self.assertIs(hr.classify_path("lib/l10n/app_zh_Hans.arb"),
                      hr.ChangeKind.ARB)

    def test_pubspec(self) -> None:
        self.assertIs(hr.classify_path("pubspec.yaml"), hr.ChangeKind.PUBSPEC)

    def test_native(self) -> None:
        self.assertIs(hr.classify_path("linux/runner/main.cc"),
                      hr.ChangeKind.NATIVE)
        self.assertIs(hr.classify_path("android/app/build.gradle.kts"),
                      hr.ChangeKind.NATIVE)

    def test_generated_l10n_ignored(self) -> None:
        self.assertIsNone(
            hr.classify_path("lib/l10n/generated/app_localizations_en.dart"))

    def test_build_output_ignored(self) -> None:
        self.assertIsNone(hr.classify_path("build/app.dill"))
        self.assertIsNone(hr.classify_path("build/x.dart"))

    def test_unrelated_file_ignored(self) -> None:
        self.assertIsNone(hr.classify_path("README.md"))
        self.assertIsNone(hr.classify_path("docs/ui-refactor/plan.md"))

    def test_leading_dot_slash_normalized(self) -> None:
        self.assertIs(hr.classify_path("./lib/main.dart"), hr.ChangeKind.DART)


class PlanTests(unittest.TestCase):
    @staticmethod
    def change(path: str) -> hr.Change:
        kind = hr.classify_path(path)
        assert kind is not None
        return hr.Change(path=path, kind=kind)

    def test_single_dart_is_hot_reload(self) -> None:
        plan = hr.plan_for([self.change("lib/main.dart")])
        self.assertIs(plan.action, hr.Action.HOT_RELOAD)
        self.assertFalse(plan.gen_l10n)
        self.assertFalse(plan.pub_get)

    def test_svg_is_hot_restart(self) -> None:
        plan = hr.plan_for([self.change("assets/icons/state.svg")])
        self.assertIs(plan.action, hr.Action.HOT_RESTART)

    def test_arb_triggers_gen_l10n_then_restart(self) -> None:
        # Live testing showed hot-reloading regenerated l10n drops the device
        # connection, so ARB must restart (after gen-l10n).
        plan = hr.plan_for([self.change("lib/l10n/app_en.arb")])
        self.assertIs(plan.action, hr.Action.HOT_RESTART)
        self.assertTrue(plan.gen_l10n)

    def test_pubspec_triggers_pub_get_and_restart(self) -> None:
        plan = hr.plan_for([self.change("pubspec.yaml")])
        self.assertIs(plan.action, hr.Action.HOT_RESTART)
        self.assertTrue(plan.pub_get)

    def test_native_is_full_restart(self) -> None:
        plan = hr.plan_for([self.change("linux/runner/main.cc")])
        self.assertIs(plan.action, hr.Action.FULL_RESTART)

    def test_dart_plus_pubspec_coalesces_to_highest_severity(self) -> None:
        plan = hr.plan_for([
            self.change("lib/main.dart"),
            self.change("pubspec.yaml"),
        ])
        self.assertIs(plan.action, hr.Action.HOT_RESTART)
        self.assertTrue(plan.pub_get)
        # Never "reload then restart": exactly one action is chosen.
        self.assertEqual(len(plan.changes), 2)

    def test_dart_plus_arb_coalesces_to_restart(self) -> None:
        plan = hr.plan_for([
            self.change("lib/main.dart"),
            self.change("lib/l10n/app_en.arb"),
        ])
        self.assertIs(plan.action, hr.Action.HOT_RESTART)
        self.assertTrue(plan.gen_l10n)

    def test_native_dominates_everything(self) -> None:
        plan = hr.plan_for([
            self.change("lib/main.dart"),
            self.change("pubspec.yaml"),
            self.change("linux/runner/main.cc"),
        ])
        self.assertIs(plan.action, hr.Action.FULL_RESTART)

    def test_summary_counts_kinds(self) -> None:
        plan = hr.plan_for([
            self.change("lib/a.dart"),
            self.change("lib/b.dart"),
            self.change("assets/icons/c.svg"),
        ])
        summary = plan.summary()
        self.assertIn("2 Dart files", summary)
        self.assertIn("1 asset file", summary)

    def test_empty_plan(self) -> None:
        plan = hr.plan_for([])
        self.assertTrue(plan.is_empty)
        self.assertIs(plan.action, hr.Action.NONE)


class DebouncerTests(unittest.TestCase):
    def test_multiple_writes_coalesce_into_one_window(self) -> None:
        debouncer = hr.Debouncer(delay_seconds=0.5)
        changes = [hr.Change(f"lib/f{i}.dart", hr.ChangeKind.DART)
                   for i in range(20)]
        debouncer.add(changes, now=0.0)
        self.assertFalse(debouncer.ready(0.2))  # still quiet
        self.assertTrue(debouncer.ready(0.6))
        taken = debouncer.take()
        self.assertEqual(len(taken), 20)
        self.assertEqual(debouncer.pending_count, 0)

    def test_late_change_extends_the_window(self) -> None:
        debouncer = hr.Debouncer(delay_seconds=0.5)
        debouncer.add([hr.Change("lib/a.dart", hr.ChangeKind.DART)], now=0.0)
        debouncer.add([hr.Change("lib/b.dart", hr.ChangeKind.DART)], now=0.4)
        self.assertFalse(debouncer.ready(0.6))  # window restarted at 0.4
        self.assertTrue(debouncer.ready(1.0))

    def test_idle_debouncer_is_not_ready(self) -> None:
        self.assertFalse(hr.Debouncer(0.5).ready(10.0))


class FileWatcherTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / "lib").mkdir()
        (self.root / "assets" / "icons").mkdir(parents=True)
        (self.root / "build").mkdir()
        (self.root / "lib" / "l10n" / "generated").mkdir(parents=True)
        (self.root / "lib" / "main.dart").write_text("void main() {}\n")
        (self.root / "assets" / "icons" / "state.svg").write_text("<svg/>\n")
        (self.root / "build" / "out.dart").write_text("// build output\n")
        (self.root / "lib" / "l10n" / "generated" / "app.dart").write_text(
            "// generated\n")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _touch(self, rel: str, content: str = "// changed\n") -> None:
        # Ensure a distinct mtime even on coarse filesystem clocks.
        time.sleep(0.01)
        (self.root / rel).write_text(content)

    def test_detects_dart_change(self) -> None:
        watcher = hr.FileWatcher(self.root, ["lib", "assets"])
        watcher.prime()
        self._touch("lib/main.dart")
        changes = watcher.poll()
        self.assertEqual([c.path for c in changes], ["lib/main.dart"])
        self.assertIs(changes[0].kind, hr.ChangeKind.DART)

    def test_detects_asset_change(self) -> None:
        watcher = hr.FileWatcher(self.root, ["lib", "assets"])
        watcher.prime()
        self._touch("assets/icons/state.svg", "<svg x/>\n")
        changes = watcher.poll()
        self.assertEqual([c.path for c in changes], ["assets/icons/state.svg"])

    def test_generated_and_build_outputs_never_reported(self) -> None:
        watcher = hr.FileWatcher(self.root, ["lib", "assets", "build"])
        watcher.prime()
        self._touch("lib/l10n/generated/app.dart", "// regen\n")
        self._touch("build/out.dart", "// rebuild\n")
        self.assertEqual(watcher.poll(), [])

    def test_no_change_no_report(self) -> None:
        watcher = hr.FileWatcher(self.root, ["lib", "assets"])
        watcher.prime()
        self.assertEqual(watcher.poll(), [])


class RunStateTests(unittest.TestCase):
    def test_pause_toggle(self) -> None:
        state = hr.RunState()
        self.assertFalse(state.auto_paused)
        state.toggle_pause()
        self.assertTrue(state.auto_paused)
        state.toggle_pause()
        self.assertFalse(state.auto_paused)

    def test_stopping_defaults_to_false(self) -> None:
        self.assertFalse(hr.RunState().stopping)


class ArgParsingTests(unittest.TestCase):
    def test_defaults(self) -> None:
        options = hr.parse_args([])
        self.assertEqual(options.device, "linux")
        self.assertEqual(options.extra, [])
        self.assertIn("lib", options.watch)

    def test_passthrough_after_separator(self) -> None:
        options = hr.parse_args(
            ["--device", "linux", "--", "--dart-define", "A=B"])
        self.assertEqual(options.extra, ["--dart-define", "A=B"])
        self.assertEqual(options.device, "linux")

    def test_command_building(self) -> None:
        command = hr.build_flutter_command("flutter", "linux", ["--verbose"])
        self.assertEqual(command, ["flutter", "run", "-d", "linux", "--verbose"])


if __name__ == "__main__":
    unittest.main()
