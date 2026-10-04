#!/usr/bin/env python3
"""Verify APK signatures and pin LT's public release certificate identity."""

import argparse
import os
from pathlib import Path
import re
import subprocess


def find_apksigner():
    roots = []
    local = Path(__file__).resolve().parents[1] / "android/local.properties"
    if local.is_file():
        for line in local.read_text().splitlines():
            if line.startswith("sdk.dir="):
                roots.append(Path(line.partition("=")[2]))
    roots.extend(Path(value) for name in ("ANDROID_HOME", "ANDROID_SDK_ROOT")
                 if (value := os.environ.get(name)))
    roots.append(Path.home() / "Android/Sdk")
    for sdk in roots:
        candidates = list((sdk / "build-tools").glob("*/apksigner"))
        if candidates:
            return max(candidates, key=lambda p: tuple(
                int(n) for n in re.findall(r"\d+", p.parent.name)))
    raise ValueError("apksigner not found in Android SDK build-tools")


def verify(apk, certificate_file, apksigner=None):
    expected = Path(certificate_file).read_text().strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("Release certificate pin must be a SHA-256 digest")
    result = subprocess.run(
        [str(apksigner or find_apksigner()), "verify", "--verbose",
         "--print-certs", str(apk)], capture_output=True, text=True, check=True)
    output = result.stdout
    if not re.search(r"^Verifies$", output, re.MULTILINE):
        raise ValueError("APK signature verification did not succeed")
    if not re.search(r"^Verified using v2 scheme .*: true$", output, re.MULTILINE):
        raise ValueError("APK Signature Scheme v2 is required")
    if not re.search(r"^Number of signers: 1$", output, re.MULTILINE):
        raise ValueError("Exactly one APK signer is required")
    # Build Tools 37 labels the signer by scheme ("V3.0 Signer"); older
    # versions print "Signer #1". Check every reported certificate identity.
    prefix = r"(?:Signer #1|V\d+(?:\.\d+)* Signer)"
    dns = re.findall(rf"^{prefix}:? certificate DN: (.+)$", output, re.MULTILINE)
    if not dns or any(re.search(r"CN\s*=\s*Android Debug\b", dn, re.IGNORECASE)
                      for dn in dns):
        raise ValueError("Android Debug certificate is forbidden for release")
    digests = re.findall(
        rf"^{prefix}:? certificate SHA-256 digest: ([0-9a-fA-F]+)$",
        output, re.MULTILINE)
    if not digests or any(digest.lower() != expected for digest in digests):
        raise ValueError("APK signer does not match LT's release certificate pin")
    print(output, end="")
    print("LT release certificate identity = VERIFIED")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk")
    parser.add_argument("--certificate-file", type=Path,
                        default=Path(__file__).resolve().parents[1] /
                        "android/release-certificate.sha256")
    parser.add_argument("--apksigner", type=Path)
    args = parser.parse_args()
    try:
        verify(args.apk, args.certificate_file, args.apksigner)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Release signing verification failed: {error}\n")
