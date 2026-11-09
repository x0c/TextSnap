#!/usr/bin/env python3
"""One-command TextSnap release, download verification and installation.

The xcconfig version and matching bilingual CHANGELOG section must already exist.

    scripts/release.py --background          # detached full release
    scripts/release.py --wait                # wait for that background run
    scripts/release.py                       # foreground full release
    scripts/release.py --verify-only         # resume after publication; no rebuild
    scripts/release.py --verify-only --no-install
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent.parent
PUBLISHER = ROOT / "scripts/publish-release.py"
SLUG = "x0c/TextSnap"


def run(argv, **kwargs):
    print("RUN", " ".join(map(str, argv)), flush=True)
    kwargs.setdefault("check", True)
    return subprocess.run(argv, cwd=ROOT, **kwargs)


def capture(argv, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    return run(argv, **kwargs)


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def version() -> tuple[str, str]:
    config = (ROOT / "Configuration/Base.xcconfig").read_text()
    marketing = re.search(r"^MARKETING_VERSION\s*=\s*(\S+)", config, re.M).group(1)
    build = re.search(r"^CURRENT_PROJECT_VERSION\s*=\s*(\d+)", config, re.M).group(1)
    return marketing, build


def save(path: Path, receipt: dict) -> None:
    path.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n")


def download(url: str, destination: Path) -> dict:
    error = None
    for attempt in range(1, 5):
        try:
            digest = hashlib.sha256()
            length = 0
            part = destination.with_suffix(destination.suffix + ".part")
            request = urllib.request.Request(url, headers={"User-Agent": "TextSnap-release"})
            with urllib.request.urlopen(request, timeout=120) as response, part.open("wb") as stream:
                for block in iter(lambda: response.read(1024 * 1024), b""):
                    stream.write(block)
                    digest.update(block)
                    length += len(block)
            part.replace(destination)
            return {"url": url, "bytes": length, "sha256": digest.hexdigest()}
        except Exception as exc:
            error = exc
            print(f"DOWNLOAD attempt {attempt} failed: {exc}", flush=True)
            if attempt < 4:
                time.sleep(attempt * 3)
    raise RuntimeError(f"Download failed after retries: {url}: {error}")


def release_assets(tag: str) -> list[str]:
    result = capture(["gh", "release", "view", tag, "-R", SLUG,
                      "--json", "assets", "--jq", ".assets[].name"])
    return sorted(result.stdout.split())


def publish(work: Path, tag: str, source: str) -> list[Path]:
    dirty = capture(["git", "status", "--porcelain"]).stdout.splitlines()
    unexpected = [line for line in dirty if line[3:] != "TASKBOARD.md"]
    if unexpected:
        raise RuntimeError("Commit source changes before release:\n" + "\n".join(unexpected))
    if capture(["git", "rev-parse", "HEAD"]).stdout.strip() != source:
        raise RuntimeError("HEAD changed during release")
    if run(["git", "rev-parse", "--verify", f"refs/tags/{tag}"], check=False).returncode != 0:
        run(["git", "tag", tag, source])
    if capture(["git", "rev-parse", f"{tag}^{{commit}}"]).stdout.strip() != source:
        raise RuntimeError(f"Local tag {tag} does not point at the tested source {source}")

    result = run([sys.executable, str(PUBLISHER), "--workdir", str(work)], check=False)
    marketing = version()[0]
    assets = [work / f"TextSnap-{marketing}.dmg",
              work / "updates" / f"TextSnap-{marketing}.zip",
              work / "updates/appcast.xml"]
    present = release_assets(tag) if all(path.is_file() for path in assets) else []
    expected = sorted(path.name for path in assets)
    if present != expected:
        raise RuntimeError(f"Publisher exited {result.returncode}; attachments are incomplete: {present}")
    if result.returncode:
        print("Publisher's final fetch failed; all assets exist, so verify bytes without rebuilding.", flush=True)
    return assets


def verify(marketing: str, build: str, tag: str, work: Path, evidence: Path) -> tuple[list[Path], dict]:
    assets = [work / f"TextSnap-{marketing}.dmg",
              work / "updates" / f"TextSnap-{marketing}.zip",
              work / "updates/appcast.xml"]
    if not all(path.is_file() for path in assets):
        raise RuntimeError("Local release artifacts are missing; run the full release first")
    expected = sorted(path.name for path in assets)
    if release_assets(tag) != expected:
        raise RuntimeError("GitHub Release attachments do not match the local artifacts")
    local_tag = capture(["git", "rev-parse", f"{tag}^{{commit}}"]).stdout.strip()
    remote_tag = capture(["git", "ls-remote", f"https://github.com/{SLUG}.git",
                          f"refs/tags/{tag}"]).stdout.split()[0]
    if remote_tag != local_tag:
        raise RuntimeError(f"Public tag {remote_tag} differs from local tag {local_tag}")
    latest = capture(["gh", "api", f"repos/{SLUG}/releases/latest", "--jq", ".tag_name"]).stdout.strip()
    if latest != tag:
        raise RuntimeError(f"Latest release is {latest}, expected {tag}")
    body = capture(["gh", "release", "view", tag, "-R", SLUG,
                    "--json", "body", "--jq", ".body"]).stdout
    if f"# TextSnap {marketing}" not in body or "### 简体中文" not in body:
        raise RuntimeError("Release notes are not the expected bilingual notes")

    downloads = evidence / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    details = {"public_tag_commit": remote_tag, "latest_release": latest,
               "release_assets": expected, "bilingual_release_notes": True, "downloads": []}
    for asset in assets:
        result = download(f"https://github.com/{SLUG}/releases/download/{tag}/{asset.name}",
                          downloads / asset.name)
        if result["sha256"] != sha(asset) or result["bytes"] != asset.stat().st_size:
            raise RuntimeError("Published bytes differ: " + asset.name)
        details["downloads"].append(result)
    details["latest_feed"] = download(
        f"https://github.com/{SLUG}/releases/latest/download/appcast.xml",
        downloads / "latest-appcast.xml")
    if (downloads / "latest-appcast.xml").read_bytes() != assets[-1].read_bytes():
        raise RuntimeError("Latest feed differs from the released appcast")
    feed = assets[-1].read_text()
    for required in (f"<sparkle:version>{build}</sparkle:version>", marketing, "edSignature", "简体中文"):
        if required not in feed:
            raise RuntimeError(f"Released appcast is missing {required}")
    details["feed_build"] = int(build)
    return assets, details


def install(dmg: Path, marketing: str, build: str, evidence: Path) -> dict:
    mount = Path(tempfile.mkdtemp(prefix="textsnap-release-mnt-"))
    os.rmdir(mount)
    export = evidence / "public-export/TextSnap.app"
    if export.parent.exists():
        shutil.rmtree(export.parent)
    export.parent.mkdir(parents=True)
    try:
        run(["hdiutil", "attach", "-readonly", "-nobrowse", str(dmg), "-mountpoint", str(mount)])
        run(["codesign", "--verify", "--deep", "--strict", str(mount / "TextSnap.app")])
        run(["xcrun", "stapler", "validate", str(mount / "TextSnap.app")])
        run(["ditto", str(mount / "TextSnap.app"), str(export)])
    finally:
        if mount.exists():
            run(["diskutil", "eject", str(mount)], check=False)
    if run(["pgrep", "-x", "TextSnap"], check=False, stdout=subprocess.DEVNULL).returncode == 0:
        run(["pkill", "-x", "TextSnap"])
    installed = Path("/Applications/TextSnap.app")
    run(["rm", "-rf", str(installed)])
    run(["ditto", str(export), str(installed)])
    run(["codesign", "--verify", "--deep", "--strict", str(installed)])
    run(["xcrun", "stapler", "validate", str(installed)])
    with (installed / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    actual = {"version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"]}
    if actual != {"version": marketing, "build": build}:
        raise RuntimeError(f"Installed version mismatch: {actual}")
    result = {"installed": actual | {"source": "anonymous public DMG"}}
    settings = Path.home() / ".config/textsnap/settings.json"
    visible = True
    if settings.is_file():
        data = json.loads(settings.read_text())
        visible = data.get("menuBar", {}).get("iconVisible", True)
    if visible:
        run(["open", str(installed)])
        time.sleep(3)
        process = capture(["pgrep", "-fl", "/Applications/TextSnap.app/Contents/MacOS/TextSnap"])
        windows = capture(["osascript", "-e",
                           'tell application "System Events" to tell process "TextSnap" to get count of windows'])
        if windows.stdout.strip() != "0":
            raise RuntimeError("Unexpected post-install Settings window")
        result["postinstall_process"] = process.stdout.strip()
        result["postinstall_window_count"] = "0"
    else:
        result["postinstall_launch"] = "skipped to avoid opening the hidden-icon recovery Settings"
    return result


def main() -> int:
    marketing, build = version()
    tag = f"v{marketing}"
    work = ROOT / "build" / f"publish-{tag}"
    evidence = ROOT / "build" / f"release-{tag}"
    evidence.mkdir(parents=True, exist_ok=True)
    receipt_path = evidence / "release-result.json"
    lock_path = evidence / "release.lock"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--background", action="store_true")
    parser.add_argument("--wait", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--no-install", action="store_true")
    args = parser.parse_args()
    if args.wait:
        with lock_path.open("r") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_SH)
        print(receipt_path.read_text())
        return 0
    if args.background:
        argv = [sys.executable, str(Path(__file__).resolve())]
        if args.verify_only:
            argv.append("--verify-only")
        if args.no_install:
            argv.append("--no-install")
        log_path = evidence / "release.log"
        with log_path.open("ab") as log:
            process = subprocess.Popen(argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True)
        (evidence / "release.pid").write_text(str(process.pid) + "\n")
        time.sleep(0.5)
        if process.poll() is not None:
            print(log_path.read_text(errors="replace")[-3000:])
            return 1
        print(f"release running: pid={process.pid}\nlog: {log_path}\nreceipt: {receipt_path}")
        return 0

    lock = lock_path.open("w")
    try:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print(f"Another release is running. Use --wait or inspect {receipt_path}", file=sys.stderr)
        return 1
    receipt = {"state": "running", "pid": os.getpid(), "version": marketing, "build": build,
               "started_at": datetime.now(timezone.utc).isoformat()}
    save(receipt_path, receipt)
    try:
        if args.verify_only:
            assets = [work / f"TextSnap-{marketing}.dmg",
                      work / "updates" / f"TextSnap-{marketing}.zip",
                      work / "updates/appcast.xml"]
        else:
            source = capture(["git", "rev-parse", "HEAD"]).stdout.strip()
            receipt["source_commit"] = source
            assets = publish(work, tag, source)
        assets, details = verify(marketing, build, tag, work, evidence)
        receipt.update(details)
        save(receipt_path, receipt)
        if not args.no_install:
            receipt.update(install(evidence / "downloads" / assets[0].name, marketing, build, evidence))
        receipt["state"] = "published_verified" if args.no_install else "published_installed"
    except Exception as error:
        receipt.update(state="failed", error=str(error))
        print("FAILED", error, flush=True)
    finally:
        receipt["finished_at"] = datetime.now(timezone.utc).isoformat()
        save(receipt_path, receipt)
        print(json.dumps(receipt, indent=2, ensure_ascii=False), flush=True)
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        lock.close()
    return 1 if receipt["state"] == "failed" else 0


if __name__ == "__main__":
    sys.exit(main())
