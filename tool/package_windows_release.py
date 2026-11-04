#!/usr/bin/env python3
"""Build a portable Windows release ZIP from a verified Flutter release."""

import argparse
import hashlib
from pathlib import Path
import zipfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    runtime = args.runtime.resolve()
    if not all((runtime / name).is_file() for name in ("lan_simple_file.exe", "data/app.so")):
        raise SystemExit("Expected a built Windows release runtime")
    if not all(character.isalnum() or character in ".-" for character in args.version):
        raise SystemExit("Invalid version")
    args.output.mkdir(parents=True, exist_ok=True)
    output = args.output / ("lan-simple-file-" + args.version + "-windows-x64.zip")
    files = []
    for file in runtime.rglob("*"):
        if not file.is_file():
            continue
        relative = file.relative_to(runtime)
        if relative.parts[0] == "data" or (
            len(relative.parts) == 1 and file.suffix.lower() in (".dll", ".exe")
        ):
            files.append((file, relative.as_posix()))
    for name in ("LICENSE", "README.md", "CHANGELOG.md"):
        files.append((root / name, name))
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for file, name in sorted(files, key=lambda entry: entry[1]):
            archive.write(file, name)
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise SystemExit("ZIP integrity check failed")
        for file, name in files:
            if hashlib.sha256(archive.read(name)).digest() != hashlib.sha256(file.read_bytes()).digest():
                raise SystemExit("ZIP content differs from build: " + name)
    checksum = hashlib.sha256(output.read_bytes()).hexdigest()
    (args.output / "SHA256SUMS.txt").write_text(
        checksum + "  " + output.name + "\n", encoding="utf-8"
    )
    print(output)
    print(checksum)


if __name__ == "__main__":
    main()
