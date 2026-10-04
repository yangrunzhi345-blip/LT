# Android release signing

Acceptance mode: Integrated Single-Agent Full-Cycle.
Scope: stable release signing, ARM64/TTS packaging preservation, CI signing gates.
Baseline: `c2cdf2d3004cc075d8a24146f791438aacdfae6f` (clean main/origin/main).

## Root cause and identity

`android/app/build.gradle.kts` explicitly selected `signingConfigs.debug` for
release. The tag workflow built that configuration without any signing Secrets
or certificate verification. A valid v2 signature therefore did not establish
the intended developer identity. This explains the Debug certificate; it does
not independently prove the cause of a particular vivo installer rejection.

Release now selects only the dedicated `release` signing configuration, loading
the ignored `android/key.properties`. `preReleaseBuild` and
`validateSigningRelease` depend on a fail-closed check for all four properties
and the keystore file. Missing credentials never select Debug signing. Debug
development does not require release credentials. Existing ABI filters and
Neural TTS architecture/resources remain unchanged.

The permanent LT certificate is:

- DN: `CN=LT Android Release, OU=Android, O=LT Dialogue, C=CN`.
- SHA-256: `1fb692595ed70152d2f43ba0a8407f879559ca583d8cd68f815aebc568e07b2d`.
- Key: RSA 4096, SHA256withRSA, validity 10,000 days.
- Container: PKCS12; alias `lt-release`.
- Public fingerprint authority: `android/release-certificate.sha256`.

Never regenerate this key for routine releases. Preserve the private key and
passwords for the lifetime of the Android update chain; maintain an encrypted
off-device backup. GitHub Secrets are not a recoverable backup of the key.
The public fingerprint is deliberately committed; it contains no private key.

## Local storage and build

The private signing directory is `~/.local/share/lt/android-signing/`, mode 0700.
It contains `lt-release.p12` and `signing-secrets.json`, mode 0600. The latter
records `storeFile`, `storePassword`, `keyAlias` and `keyPassword` privately.
`android/key.properties` is mode 0600, ignored by Git, and references that stable
keystore. `storeFile` resolves relative to `android/` unless it is absolute.
Root ignore rules additionally protect keystores, PKCS12 files and signing
credentials wherever they accidentally appear in the repository.

Build and verify with:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
python3 -m unittest discover -s scripts -p test_android_release_signing.py
python3 scripts/verify_android_release_signing.py build/app/outputs/flutter-apk/app-release.apk
python3 scripts/verify_android_arm64_apk.py build/app/outputs/flutter-apk/app-release.apk
git diff --check
```

The signing verifier finds the newest available Build Tools in the project's
SDK, SDK environment variables or the usual home SDK directory. It invokes
`apksigner verify --verbose --print-certs`, requires verification, v2, exactly
one signer, no Android Debug DN and an exact match to the public fingerprint.
It understands both legacy and Build Tools 37 certificate output formats.

## GitHub Actions

Repository Actions Secrets were configured securely from the private local
store, through subprocess standard input, without logging their values:

| Secret | Value source |
| --- | --- |
| `LT_ANDROID_KEYSTORE_BASE64` | Base64 of the persisted `lt-release.p12` |
| `LT_ANDROID_KEYSTORE_PASSWORD` | Private `storePassword` |
| `LT_ANDROID_KEY_ALIAS` | Private `keyAlias` (`lt-release`) |
| `LT_ANDROID_KEY_PASSWORD` | Private `keyPassword` |

CI refuses missing/empty signing material, decodes the encrypted keystore under
`RUNNER_TEMP`, writes private properties with umask 0077 and removes both files
in an `always()` cleanup step. Signing materials are never included in uploaded
artifacts. After building, certificate and ABI/TTS verification must pass before
an APK is uploaded or published. A wrongly configured key fails the fingerprint
gate, even if it has a plausible certificate name.

Tag pushes build the tagged commit and can publish a new Release. Manual
`verify_only=true` builds current main with the real signing Secrets, runs all
gates and uploads artifacts without changing tags or GitHub Releases:

```sh
gh workflow run release-arm64.yml --ref main -f tag=v1.1.18 -f verify_only=true
```

The tag input must match the source's pubspec version. For a future version,
change this input accordingly. To publish manually, use `verify_only=false`
and an existing new version tag pointing to the approved source. Existing
Releases are never overwritten. This task does not bump version 1.1.18+21 or
replace the previous Debug-signed v1.1.18 Release asset.

## Validation and migration

Local validation passed: `flutter pub get`, analyze (no issues), full regression
(3387 PASS, two existing conditional skips), ARM64 Release build, signing gate,
ABI gate and `git diff --check`. Nine signing-gate regression checks pass.
A real previous Debug-signed APK is rejected by the new gate. Removing the
private properties temporarily makes `:app:preReleaseBuild` fail for the exact
missing-signing reason; the original private file was restored afterward.

The final APK verifies with one LT signer: v2 and v3 true, v1/v3.1/v3.2/v4 false
with Build Tools 37. Eight packaged native libraries are ARM64 ELF64 only.
Sherpa C/C++ APIs and ONNX Runtime are present and byte-identical to the previous
runtime-validated APK. All 126 Sherpa FFI symbols and packaged native dependencies
are present. No TTS library, model resource, fallback or architecture was removed.
16 KB zip alignment verification passes.

Final local APK: `build/app/outputs/flutter-apk/app-release.apk`, 54,577,665 bytes.
SHA-256: `2599e69ca63536be319988326bfc04ad08339eac53b1410bfc9b9d49c35bb021`.
No Android device was connected, so this task did not run `adb install` or make
a claim about physical-device installation. Remote CI evidence is checked after
the commit/push and recorded in the delivery report.

The new certificate intentionally differs from the old Debug certificate.
Android normally requires the same signing identity for an in-place update:
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` is therefore expected when updating an old
Debug-signed install. This is a one-time transition. Back up/export user data
before the user chooses to uninstall the old package and first install this
officially signed build. Never uninstall automatically or bypass Android signing
checks. Subsequent official versions must reuse this exact release key.

References: [Flutter Android signing](https://docs.flutter.dev/deployment/android#sign-the-app),
[Android app signing](https://developer.android.com/studio/publish/app-signing),
[apksigner](https://developer.android.com/tools/apksigner).
