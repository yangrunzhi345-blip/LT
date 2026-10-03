#!/usr/bin/env python3
"""Reject non-ARM64 APKs and missing Neural TTS native libraries."""

import argparse
import struct
import zipfile


def verify(apk_path):
    required = {
        "libflutter.so",
        "libapp.so",
        "libsherpa-onnx-c-api.so",
        "libsherpa-onnx-cxx-api.so",
        "libonnxruntime.so",
    }
    with zipfile.ZipFile(apk_path) as apk:
        entries = [
            name for name in apk.namelist()
            if name.startswith("lib/") and not name.endswith("/")
        ]
        if not entries:
            raise ValueError("APK has no native libraries")
        for name in entries:
            if not name.startswith("lib/arm64-v8a/"):
                raise ValueError(f"Forbidden Android ABI: {name}")
            data = apk.read(name)
            if (len(data) < 20 or data[:4] != b"\x7fELF"
                    or data[4:6] != b"\x02\x01"
                    or struct.unpack_from("<H", data, 18)[0] != 183):
                raise ValueError(f"Native library is not AArch64 ELF64: {name}")
        packaged = {name.rsplit("/", 1)[-1] for name in entries}
        missing = required - packaged
        if missing:
            raise ValueError(f"Missing required native libraries: {sorted(missing)}")
        print("arm64-v8a = YES")
        print("armeabi-v7a = NO")
        print("x86 = NO")
        print("x86_64 = NO")
        print("Neural TTS ARM64 native libraries = YES")
        print("\n".join(sorted(entries)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk")
    args = parser.parse_args()
    try:
        verify(args.apk)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f"APK verification failed: {error}\n")
