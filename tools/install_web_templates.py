#!/usr/bin/env python3
"""Fetch only the two Web templates from Godot's official release ZIP.

Uses HTTP ranges rather than downloading unrelated platform templates.
zipfile validates each extracted member's CRC. All files stay in the project.
"""
import io
import pathlib
import urllib.request
import zipfile

VERSION = "4.7.2"
ROOT = pathlib.Path(__file__).resolve().parents[1]
URL = (
    f"https://github.com/godotengine/godot-builds/releases/download/"
    f"{VERSION}-stable/Godot_v{VERSION}-stable_export_templates.tpz"
)


class RemoteZip(io.RawIOBase):
    def __init__(self, url):
        response = urllib.request.urlopen(
            urllib.request.Request(url, method="HEAD"), timeout=60
        )
        self.url = response.url
        self.length = int(response.headers["Content-Length"])
        self.position = 0

    def seekable(self):
        return True

    def seek(self, offset, whence=0):
        self.position = (
            offset if whence == 0
            else self.position + offset if whence == 1
            else self.length + offset
        )
        return self.position

    def tell(self):
        return self.position

    def read(self, size=-1):
        end = self.length - 1 if size < 0 else min(self.position + size, self.length) - 1
        if end < self.position:
            return b""
        request = urllib.request.Request(
            self.url, headers={"Range": f"bytes={self.position}-{end}"}
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            if response.status != 206:
                raise RuntimeError("Release server does not support HTTP range requests")
            data = response.read()
        self.position += len(data)
        return data


def main():
    target = ROOT / ".tools" / "templates"
    target.mkdir(parents=True, exist_ok=True)
    names = ["web_nothreads_release.zip", "web_nothreads_debug.zip"]
    if all((target / name).exists() for name in names):
        print(f"Godot {VERSION} Web templates already available at {target}")
        return
    with zipfile.ZipFile(RemoteZip(URL)) as archive:
        for name in names:
            print(f"Downloading Godot {VERSION}: {name}", flush=True)
            data = archive.read(f"templates/{name}")
            with zipfile.ZipFile(io.BytesIO(data)) as template:
                if template.testzip():
                    raise RuntimeError(f"Invalid Web template: {name}")
            (target / name).write_bytes(data)
    print(f"Templates ready: {target}")


if __name__ == "__main__":
    main()
