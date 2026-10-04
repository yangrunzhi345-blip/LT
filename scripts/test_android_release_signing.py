"""Regression checks for the release publication signing gate."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from verify_android_release_signing import verify


class ReleaseSigningGateTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.pin = Path(self.directory.name) / "certificate.sha256"
        self.pin.write_text("ab" * 32 + "\n")
        self.output = (
            "Verifies\n"
            "Verified using v2 scheme (APK Signature Scheme v2): true\n"
            "Number of signers: 1\n"
            "Signer #1 certificate DN: CN=LT Android Release, O=LT Dialogue\n"
            f"Signer #1 certificate SHA-256 digest: {'ab' * 32}\n"
        )

    def run_gate(self, output):
        result = subprocess.CompletedProcess([], 0, stdout=output, stderr="")
        with patch("verify_android_release_signing.subprocess.run",
                   return_value=result), patch("builtins.print"):
            verify("app.apk", self.pin, "apksigner")

    def test_accepts_pinned_release_certificate(self):
        self.run_gate(self.output)

    def test_accepts_build_tools_37_signer_format(self):
        self.run_gate(self.output.replace("Signer #1", "V3.0 Signer:"))

    def test_rejects_debug_certificate_even_if_pinned(self):
        with self.assertRaisesRegex(ValueError, "Debug certificate"):
            self.run_gate(self.output.replace("CN=LT Android Release",
                                              "CN=Android Debug"))

    def test_rejects_unpinned_certificate(self):
        with self.assertRaisesRegex(ValueError, "certificate pin"):
            self.run_gate(self.output.replace("ab" * 32, "cd" * 32))

    def test_rejects_absent_v2_signature(self):
        with self.assertRaisesRegex(ValueError, "v2 is required"):
            self.run_gate(self.output.replace(
                "Scheme v2): true", "Scheme v2): false"))

    def test_rejects_multiple_signers(self):
        with self.assertRaisesRegex(ValueError, "one APK signer"):
            self.run_gate(self.output.replace("signers: 1", "signers: 2"))

    def test_rejects_missing_certificate(self):
        with self.assertRaisesRegex(ValueError, "certificate is forbidden"):
            self.run_gate("\n".join(line for line in self.output.splitlines()
                                    if "certificate DN" not in line))

    def test_rejects_malformed_pin(self):
        self.pin.write_text("not-a-certificate")
        with self.assertRaisesRegex(ValueError, "SHA-256 digest"):
            self.run_gate(self.output)

    def test_propagates_apksigner_failure(self):
        with patch("verify_android_release_signing.subprocess.run",
                   side_effect=subprocess.CalledProcessError(1, "apksigner")):
            with self.assertRaises(subprocess.CalledProcessError):
                verify("app.apk", self.pin, "apksigner")


if __name__ == "__main__":
    unittest.main()
