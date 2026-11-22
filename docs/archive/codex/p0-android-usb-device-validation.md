# P0 — Android USB 实机端到端验收

Status: PARTIAL — Real Device End-to-End Validation.
Acceptance mode: Real Device End-to-End Validation (real USB device, real install,
real UI, real LLM).
No app uninstall, no data clearing, no user-resource deletion, no APK publication and no
Release were performed.

## 1. Git baseline

- Working tree: clean (`git status --short` empty).
- Branch: `main`; `HEAD = origin/main = 38769c9f74cd1fb17408a6ce87ba4f5447b1d739`.
- `flutter pub get` did not modify `pubspec.lock`.
- The device was running the same package signed with the same release key (v1.2.05,
  versionCode 27) before the upgrade.

## 2. Device and environment

Evidence: `evidence/p0-android-usb/device_baseline.txt`.

- USB serial: `10AF7M0DNH003DL` (state `device` after `adb kill-server` re-triggered the
  on-device USB-debugging authorization; initially `unauthorized`).
- Model: `V2507A` (vivo iQOO Z10 Turbo+, `lsusb 2d95:6001`).
- Android: `16` (SDK 36).
- ABI: `arm64-v8a` only (`ro.product.cpu.abilist = arm64-v8a`).
- ADB 1.0.41; Flutter 3.44.8 / Dart 3.12.2; Android SDK 36.1.0; JDK 21.
  `flutter doctor -v`: Flutter ✓, Linux ✓, connected device `android-arm64 Android 16 (API 36) ✓`;
  Android licenses warning only (build succeeded regardless); Chrome ✗ (unrelated).

## 3. Signing compatibility (pre-install)

The app package `com.example.lt_dialogue` was **already installed** with real user data.
Before installing, the installed APK was pulled and its signer compared with the configured
release keystore (`android/key.properties` → `~/.local/share/lt/android-signing/lt-release.p12`):

- Installed signer SHA-256: `1fb692595ed70152d2f43ba0a8407f879559ca583d8cd68f815aebc568e07b2d`
- Keystore cert SHA-256: identical.
- Built APK signer SHA-256: identical.

→ Signature-compatible upgrade; `adb install -r` (data-preserving) is safe. No uninstall,
no data clear.

## 4. ARM64 APK build and install

Evidence: `evidence/p0-android-usb/apk_verification.txt`.

- Command: `flutter build apk --release --target-platform android-arm64` → success, 85.8s.
- Output: `build/app/outputs/flutter-apk/app-release.apk`, 54 780 142 bytes.
- `aapt2 dump badging`: `package com.example.lt_dialogue versionCode=28 versionName=1.2.06`,
  `native-code: 'arm64-v8a'` (no arm32/x86).
- Native TTS libraries intact: `libonnxruntime.so`, `libsherpa-onnx-c-api.so`,
  `libsherpa-onnx-cxx-api.so` (plus `libsqlite3.so`, `libapp.so`, …).
- Install: `adb -s 10AF7M0DNH003DL install -r app-release.apk` → `Success`.
- Post-install `dumpsys package`: `versionName=1.2.06 versionCode=28`; `firstInstallTime`
  unchanged (`2026-10-10 08:29:36`) → **data preserved**, only `lastUpdateTime` advanced.

## 5. On-device environment readiness

- App launched (PID 9287), `MainActivity` resumed, Impeller/Vulkan backend, **no
  exceptions** in logcat.
- LLM provider already configured and preserved: Settings → 生成 shows
  “DeepSeek 官方 API — 已就绪”, model `deepseek-flash`, endpoint `https://api.deepseek.com`,
  key present (encrypted; not read or logged).
- In-app “测试连接” → **“连接成功！耗时 1445ms，服务状态极佳。”** (real network call).

## 6. Scenario results and evidence

UI automation: the Flutter UI exposes semantics through Android accessibility, so
`uiautomator dump` + `adb shell input tap` drove the app without mocks.

### 6.1 Resource library / readiness — PASS (readiness), compression NOT exercised

Evidence: `evidence/p0-android-usb/library_readiness.txt`.

All three preserved resources show “已准备完成 · 可用于冒险”:

- 世界观 “德尔兰特世界设定集” — **~19 800 字** (near the 20 000 nominal budget).
- 角色 “艾尔——…” — ~7 800 字.
- 角色 “利亚——…” — ~7 800 字.

No resource shows a stuck `preparing`, and none required compression because each is
within the absolute budget (character 24 000 / worldview 60 000). The **overflow →
compression → recovery** path was therefore **not exercised on the device** (see §7).

### 6.2 Adventure assembly → start → first dialogue — PASS (real LLM)

Evidence: `evidence/p0-android-usb/adventure_start_and_dialogue.log` (sanitized).

Driven entirely through the real UI wizard:

1. 启动向导 → 从资料库选择 → bound worldview `res_cre_1791592249503814_1`.
2. 角色阵容 → selected 艾尔 (protagonist radio `checked=true`) + 利亚 (companion).
3. 序章分支 → “AI 生成序章与分支” → real LLM produced the prologue + 3 action branches.
4. 装配总览 showed the frozen config (world / protagonist / companion / prologue).
5. 踏入冒险 → the authoritative start boundary executed and the app log recorded:

```
[AdventureStart][CREATE][GATE_BEGIN]
[AdventureStart][CREATE][GATE_DONE]            (~60 ms; resources already ready)
[AdventureStart][CREATE][ASSEMBLED_DONE] {definitions: 0, selected: 2, relationships: 1}
[AdventureStart][CREATE][PERSIST_DONE]  {adventureId: 2}
[AdventureStart][CREATE][WORLD_ENTRIES_DONE]
[AdventureStart][CREATE][COMPLETE]      {adventureId: 2}
[AdventureStart][BOOTSTRAP_DONE]        {adventureId: 2}
[AdventureStart][OPENING_DONE]          {adventureId: 2, seeded: true}
```

6. First turn: selected an action option → real LLM streaming turn; log recorded:

```
[LengthGuard] initial=701 required=400 hardMax=1000 passed=true
[ChatEngine] ... 第 1 轮 ... 实际: 701 ... 达标: ✅ 是
```

The assistant prose (“艾尔没有再多犹豫…”, “第一幕·裂谷封印”, mood 😨恐惧) rendered, and the
runtime header initialized (`生命值 100/100`, `魔力值 100/100`). Input returned to 发送.

No `Exception`, `E/flutter` or `AndroidRuntime` app crash occurred (the only AndroidRuntime
lines are my own `uiautomator` helper processes).

### 6.3 App restart and re-entry recovery — PASS

- `adb shell am force-stop com.example.lt_dialogue` (process killed) → relaunch → new PID
  11275, clean start, no crash.
- The created adventure persisted as “继续未尽的冒险” (saved `2026-10-10T14:49:52Z`).
- 继续探索 re-entered the adventure and restored the persisted conversation (序章 + turn 1);
  logcat showed **no new LLM/generation activity** on re-entry (history restored, not
  re-generated). Resources still “已准备完成”.

### 6.4 Not verified on device

- **Test A (fresh 8 000-budget generation)** — NOT VERIFIED on device. Not automated:
  the AI-create budget control is a custom Flutter slider that did not respond to
  `adb input tap/swipe`; the soft IME intercepted early attempts and a later swipe triggered
  a vivo system overlay. Per the task rule, the scenario was **not faked** and the user
  database was **not** modified.
- **Test B (fresh 20 000-budget generation)** — NOT VERIFIED on device as a *fresh
  generation*. Partial high-capacity evidence: the preserved **~19 800-char** worldview
  reached `ready`, assembled, started and produced a first real-LLM dialogue (§6.2).
- **超限 Part 处理 (Test C)** — NOT VERIFIED on device. A >12 000-character single Part
  cannot be produced through normal UI generation, and the user database must not be edited
  to fake it. This path is covered by host real-SQLite integration tests (commit `38769c9`,
  `adventure_compression_lifecycle_sqlite_test.dart`), which are **device-independent**.
- **压缩状态恢复** — NOT VERIFIED on device: no overflow resource existed, so the
  compression lifecycle never ran.
- **失败重试（注入 LLM 失败）** — NOT VERIFIED on device: deterministic LLM failure
  injection is not available through the UI.

## 7. Logs and diagnostics

- Captured with `adb logcat` filtered to the app PID; markers used by the project:
  `[AdventureStart][…]`, `[TrackedStateBootstrap][…]`, `[ChatEngine]`, `[LengthGuard]`.
- `GenerationDiagnostics` markers are debug/profile-only and are no-ops in release, so they
  are not expected in a release APK.
- No API key, Authorization header, prompt or private body text is recorded in the evidence;
  the saved log was filtered and redacted.

## 8. Fixes

No device-reproduced defect required a fix. No production or test code was changed for this
device validation. The only repository change is the report plus evidence files.

## 9. Automated regression (host, unchanged)

- `flutter test --no-pub`: 3 689 passed / 2 skipped / 0 failed (commit `38769c9`).
- These are host-level real-SQLite integration tests and are explicitly **not** device
  validation.

## 10. Automation vs manual scope

- Automated on device: USB detection, build, install, launch, full UI navigation for the
  assembly/start/dialogue loop, log capture, restart/re-entry.
- Blocked for automation (manual user step required): precise budget-slider setting on the
  AI-create screen.

## 11. Residual risk / unfinished

- Fresh 8 000 / 20 000-budget generation closed loop is unverified on the real device.
- The device compression/overflow recovery path is unverified on the real device because a
  valid ≥ 24 001-character resource was not available and must not be fabricated.
- One additional test adventure (id 2) was created on the device during validation; existing
  user resources, character cards, worldviews and the pre-existing adventure were not
  modified or deleted. No data was cleared or reset.

## 12. FINAL STATUS

| 验收项目 | 结论 | 证据 |
|---|---|---|
| USB 设备连接 | **PASS** | device_baseline.txt (V2507A, Android 16, arm64-v8a) |
| ARM64 APK 构建 | **PASS** | apk_verification.txt (arm64-v8a only, signer match, TTS libs) |
| APK 安装与启动 | **PASS** | install -r Success; versionCode 28; firstInstallTime preserved; clean launch |
| 8,000 字完整闭环 | **NOT VERIFIED** | budget slider not UI-automatable; not faked |
| 20,000 字完整闭环 | **NOT VERIFIED (partial)** | preserved ~19 800 worldview fully closed loop PASS; no fresh 20 000 generation |
| 超限 Part 处理 | **NOT VERIFIED (device)** | covered by host real-SQLite tests only |
| 压缩状态恢复 | **NOT VERIFIED (device)** | no overflow resource; no compression ran |
| 冒险装配与启动 | **PASS** | AdventureStart GATE/ASSEMBLED/PERSIST/OPENING markers |
| 首轮真实 LLM 对话 | **PASS** | LengthGuard 701 / ChatEngine 第1轮 达标 + rendered prose |
| 应用重启与恢复 | **PASS** | force-stop → relaunch → history restored, no re-generation |

**Overall: PARTIAL.** The highest-value real-device integration — a high-capacity (~19 800)
resource going through readiness → assembly → start → first real-LLM dialogue, plus
data-preserving upgrade and restart recovery — is proven. The fresh budget-configured
generation and the device compression/overflow paths are explicitly NOT VERIFIED and are not
claimed as resolved.
