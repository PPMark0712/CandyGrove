#!/usr/bin/env python3
"""Build, test, and locally serve the Godot game (never implements gameplay)."""
import argparse
import functools
import http.server
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "web"
LOGS = ROOT / ".tools" / "logs"


def godot():
    executable = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    portable = ROOT / ".tools" / "godot" / "Godot"
    macos = pathlib.Path("/Applications/Godot.app/Contents/MacOS/Godot")
    if not executable and portable.exists():
        executable = str(portable)
    if not executable and macos.exists():
        executable = str(macos)
    if not executable:
        raise RuntimeError("Godot 4.7.2 is required. Set GODOT_BIN to the executable path.")
    version = subprocess.check_output([executable, "--version"], text=True).strip()
    if not version.startswith("4.7.2."):
        raise RuntimeError(f"Expected Godot 4.7.2 to match Web templates, found {version}")
    return executable


def run_engine(executable, name, *arguments):
    LOGS.mkdir(parents=True, exist_ok=True)
    command = [
        executable, "--headless", "--path", str(ROOT),
        "--log-file", str(LOGS / f"{name}.log"), *arguments,
    ]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=120)
    output = result.stdout + result.stderr
    print(output, end="", flush=True)
    # The editor's optional ObjectDB profiler may lack user:// access in a sandbox.
    # Keep its message visible, but do not mistake it for a game/export failure.
    errors = [
        line for line in output.splitlines()
        if "ERROR:" in line and "Could not create ObjectDB Snapshots directory" not in line
    ]
    if result.returncode or errors:
        raise RuntimeError(f"Godot {name} failed; see {LOGS / (name + '.log')}")


def test(executable):
    run_engine(executable, "import", "--editor", "--import")
    run_engine(executable, "test-forest", "--script", "tests/test_forest.gd")
    run_engine(executable, "test-game", "--script", "tests/test_game.gd")


def build(executable):
    subprocess.run([sys.executable, str(ROOT / "tools/install_web_templates.py")], check=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD.parent / ".gdignore").touch()
    run_engine(executable, "import", "--editor", "--import")
    run_engine(executable, "export", "--export-release", "Web", str(BUILD / "index.html"))
    for name in ["index.html", "index.js", "index.wasm", "index.pck"]:
        if not (BUILD / name).is_file():
            raise RuntimeError(f"Missing Godot export artifact: {name}")
    (BUILD / ".nojekyll").touch()
    print(f"Godot Web build ready: {BUILD}", flush=True)


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["build", "test", "serve", "play"], nargs="?", default="play")
    parser.add_argument("--port", type=int, default=8077)
    args = parser.parse_args()
    if args.action in ("test", "build", "play"):
        executable = godot()
        if args.action == "test":
            test(executable)
        else:
            build(executable)
    if args.action in ("serve", "play"):
        if not (BUILD / "index.html").exists():
            raise RuntimeError("No Web build found. Run: python3 tools/web.py build")
        handler = functools.partial(Handler, directory=str(BUILD))
        with http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
            print(f"Play at http://127.0.0.1:{args.port} (Ctrl+C to stop)", flush=True)
            server.serve_forever()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
