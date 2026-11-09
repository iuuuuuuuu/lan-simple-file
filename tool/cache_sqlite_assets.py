#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Cache the locked sqlite3 hook's exact binaries via the GitHub asset API."""

import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def download(url, destination, *, binary=False):
    subprocess.run(
        [
            "curl", "--fail", "--location", "--silent", "--show-error",
            "--retry", "4", "--retry-all-errors", "--retry-delay", "2",
            "--connect-timeout", "15", "--max-time", "60",
            "-H", "Accept: application/octet-stream" if binary else
            "Accept: application/vnd.github+json",
            "--output", str(destination), url,
        ],
        check=True,
    )


def locked_assets(root):
    config = root / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
    package = next(p for p in packages if p["name"] == "sqlite3")
    uri = urlparse(urljoin(config.as_uri(), package["rootUri"]))
    if uri.scheme != "file" or uri.netloc:
        raise ValueError("Expected a local sqlite3 package")
    package_root = Path(url2pathname(uri.path))
    source = (package_root / "lib/src/hook/asset_hashes.dart").read_text(
        encoding="utf-8"
    )
    tag = re.search(r"const String\? releaseTag = '([^']+)';", source)[1]
    if not re.fullmatch(r"sqlite3-[0-9.]+", tag):
        raise ValueError("Unexpected sqlite3 release tag")
    literal = re.search(
        r"assetNameToSha256Hash\s*=\s*({.*?});", source, re.DOTALL
    )[1]
    hashes = ast.literal_eval(literal)
    if not isinstance(hashes, dict) or not all(
        isinstance(name, str) and re.fullmatch(r"[a-f0-9]{64}", value)
        for name, value in hashes.items()
    ):
        raise ValueError("Invalid locked asset hashes")
    return tag, hashes


def cache_assets(root, platform):
    tag, hashes = locked_assets(root)
    names = ["sqlite3.x64.windows.dll"] if platform == "windows" else [
        "libsqlite3.arm.android.so", "libsqlite3.arm64.android.so",
        "libsqlite3.x64.android.so", "libsqlite3.x64.linux.so",
    ]
    cached_name = "sqlite3.dll" if platform == "windows" else "libsqlite3.so"
    cache = root / ".dart_tool/hooks_runner/shared/sqlite3/build"
    with tempfile.TemporaryDirectory(prefix="sqlite-assets-") as temporary:
        temporary = Path(temporary)
        metadata = None
        for name in names:
            expected = hashes[name]
            destination = cache / f"download-{expected[:8]}" / cached_name
            if destination.is_file() and digest(destination) == expected:
                print(f"Verified cached {name}")
                continue
            if metadata is None:
                manifest = temporary / "release.json"
                download(
                    f"https://api.github.com/repos/simolus3/sqlite3.dart/releases/tags/{tag}",
                    manifest,
                )
                metadata = json.loads(manifest.read_text(encoding="utf-8"))
                if metadata.get("tag_name") != tag:
                    raise ValueError("Unexpected upstream release")
            asset = next(a for a in metadata["assets"] if a["name"] == name)
            if asset.get("digest") != f"sha256:{expected}":
                raise ValueError(f"Upstream digest differs from lock: {name}")
            asset_id = asset["id"]
            if not isinstance(asset_id, int) or asset_id <= 0:
                raise ValueError("Invalid upstream asset ID")
            staged = temporary / name
            download(
                f"https://api.github.com/repos/simolus3/sqlite3.dart/releases/assets/{asset_id}",
                staged, binary=True,
            )
            if digest(staged) != expected:
                raise ValueError(f"Downloaded digest differs from lock: {name}")
            destination.parent.mkdir(parents=True, exist_ok=True)
            # Replace only the verified cache entry, never the installed package.
            destination.write_bytes(staged.read_bytes())
            print(f"Cached and verified {name}: {expected}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["windows", "android"], required=True)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    arguments = parser.parse_args()
    cache_assets(arguments.root.resolve(), arguments.platform)
