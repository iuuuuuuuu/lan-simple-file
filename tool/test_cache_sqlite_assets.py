#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Verify the release dependency cache fails closed on bad upstream content."""

import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import cache_sqlite_assets as cache


class CacheAssetsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="sqlite-cache-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        package = self.root / "package with spaces"
        hook = package / "lib/src/hook"
        hook.mkdir(parents=True)
        names = [
            "sqlite3.x64.windows.dll", "libsqlite3.arm.android.so",
            "libsqlite3.arm64.android.so", "libsqlite3.x64.android.so",
            "libsqlite3.x64.linux.so",
        ]
        self.binaries = {name: name.encode("ascii") for name in names}
        self.hashes = {
            name: hashlib.sha256(content).hexdigest()
            for name, content in self.binaries.items()
        }
        (hook / "asset_hashes.dart").write_text(
            "const String? releaseTag = 'sqlite3-3.5.2';\n"
            "const assetNameToSha256Hash = " + repr(self.hashes) + ";\n",
            encoding="utf-8",
        )
        (self.root / ".dart_tool").mkdir()
        (self.root / ".dart_tool/package_config.json").write_text(
            json.dumps({"packages": [{
                "name": "sqlite3", "rootUri": package.as_uri() + "/",
            }]}), encoding="utf-8",
        )
        self.metadata = {
            "tag_name": "sqlite3-3.5.2",
            "assets": [
                {"name": name, "id": index + 1, "digest": f"sha256:{value}"}
                for index, (name, value) in enumerate(self.hashes.items())
            ],
        }

    def destination(self, name):
        filename = "sqlite3.dll" if name.endswith(".dll") else "libsqlite3.so"
        return (
            self.root / ".dart_tool/hooks_runner/shared/sqlite3/build"
            / f"download-{self.hashes[name][:8]}" / filename
        )

    def download(self, url, destination, *, binary=False):
        if binary:
            asset_id = int(url.rsplit("/", 1)[1])
            asset = next(a for a in self.metadata["assets"] if a["id"] == asset_id)
            destination.write_bytes(self.binaries[asset["name"]])
        else:
            destination.write_text(json.dumps(self.metadata), encoding="utf-8")

    def test_verified_windows_cache_can_be_reused_offline(self):
        with patch.object(cache, "download", side_effect=self.download):
            cache.cache_assets(self.root, "windows")
        name = "sqlite3.x64.windows.dll"
        self.assertEqual(self.destination(name).read_bytes(), self.binaries[name])
        with patch.object(cache, "download") as download:
            cache.cache_assets(self.root, "windows")
        download.assert_not_called()

    def test_all_android_and_linux_host_architectures_are_verified(self):
        with patch.object(cache, "download", side_effect=self.download) as download:
            cache.cache_assets(self.root, "android")
        self.assertEqual(download.call_count, 5)
        for name, content in self.binaries.items():
            if name.endswith(".so"):
                self.assertEqual(self.destination(name).read_bytes(), content)

    def test_metadata_cannot_replace_locked_digest(self):
        self.metadata["assets"][0]["digest"] = "sha256:" + "0" * 64
        with patch.object(cache, "download", side_effect=self.download) as download:
            with self.assertRaisesRegex(ValueError, "Upstream digest differs"):
                cache.cache_assets(self.root, "windows")
        self.assertEqual(download.call_count, 1)
        self.assertFalse(self.destination("sqlite3.x64.windows.dll").exists())

    def test_gateway_html_is_rejected_without_replacing_existing_cache(self):
        name = "sqlite3.x64.windows.dll"
        destination = self.destination(name)
        destination.parent.mkdir(parents=True)
        destination.write_bytes(b"previous incomplete download")
        self.binaries[name] = b"<html><h1>504 Gateway Time-out</h1></html>"
        with patch.object(cache, "download", side_effect=self.download):
            with self.assertRaisesRegex(ValueError, "Downloaded digest differs"):
                cache.cache_assets(self.root, "windows")
        self.assertEqual(destination.read_bytes(), b"previous incomplete download")

    def test_corrupt_cache_is_replaced_only_after_verification(self):
        name = "sqlite3.x64.windows.dll"
        destination = self.destination(name)
        destination.parent.mkdir(parents=True)
        destination.write_bytes(b"corrupt")
        with patch.object(cache, "download", side_effect=self.download):
            cache.cache_assets(self.root, "windows")
        self.assertEqual(destination.read_bytes(), self.binaries[name])

    def test_transport_error_leaves_no_cache_entry(self):
        failure = subprocess.CalledProcessError(22, "curl")
        with patch.object(cache, "download", side_effect=failure):
            with self.assertRaises(subprocess.CalledProcessError):
                cache.cache_assets(self.root, "windows")
        self.assertFalse(self.destination("sqlite3.x64.windows.dll").exists())

    def test_wrong_release_is_rejected(self):
        self.metadata["tag_name"] = "sqlite3-0.0.0"
        with patch.object(cache, "download", side_effect=self.download):
            with self.assertRaisesRegex(ValueError, "Unexpected upstream release"):
                cache.cache_assets(self.root, "windows")
        self.assertFalse(self.destination("sqlite3.x64.windows.dll").exists())


if __name__ == "__main__":
    unittest.main()
