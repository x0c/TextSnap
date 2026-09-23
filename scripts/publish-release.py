#!/usr/bin/env python3
"""TextSnap public-release pipeline (macOS release machine only).

One command on the release Mac does the whole chain for the locked version::

    scripts/publish-release.py               # full run (build, sign, notarize, upload)
    scripts/publish-release.py --local-only  # stop after the notarized dmg, touch nothing remote

Order (each step aborts the run on failure):
  0. prechecks (Developer ID cert, notary credentials, gh auth, single-instance lock)
  1. version consistency (xcconfig is the single source) + tag-pushed check + anti-rollback
  2. xcodegen generate + archive + exportArchive (route A: re-signs nested Sparkle helpers)
  3. signature self-checks (Developer ID + runtime + timestamp, no get-task-allow,
     per-component check of Sparkle's nested executables)
  4. notarize .app + staple
  5. re-zip stapled .app -> EdDSA sign + appcast.xml via official generate_appcast
  6. dmg (staged .app + /Applications symlink) -> notarize + staple + Gatekeeper final check
  7. (full mode) tag push, empty Release first, per-file --clobber uploads, attachment audit
  8. (full mode, repo exists) anonymous download check of appcast/zip/dmg
  9. print closing summary (version, attachment count, latest + feed pointers)

Credentials come from the environment only; nothing private is hardcoded, so this
file is safe to publish in the public repo::

    TEXTSNAP_NOTARY_KEY        path to the App Store Connect Team Key .p8 (notarization)
    TEXTSNAP_NOTARY_KEY_ID     Key ID of that key
    TEXTSNAP_NOTARY_ISSUER     Issuer ID of that key
    TEXTSNAP_SPARKLE_ED_KEY_FILE  path to the base64 Ed25519 seed file (update signing);
                               defaults to ~/.config/textsnap/sparkle-ed25519-seed

Unattended runs (agents, cron) need no exports: when any TEXTSNAP_NOTARY_*
variable is missing, the script falls back to ~/.config/textsnap/notary.env
(plain KEY=VALUE lines, mode 600, never committed). Explicit environment
variables always win; a missing file changes nothing.

Non-interactive throughout: on missing credentials the script stops and prints
the exact gap plus the self-help command instead of prompting.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "TextSnap"
BUNDLE_ID = "top.caozc.TextSnap"
GITHUB_SLUG = "x0c/TextSnap"
SCHEME = "TextSnap"
PROJECT = REPO_ROOT / "TextSnap.xcodeproj"

SPARKLE_VERSION = "2.10.0"
SPARKLE_TARBALL_URL = (
    f"https://github.com/sparkle-project/Sparkle/releases/download/"
    f"{SPARKLE_VERSION}/Sparkle-{SPARKLE_VERSION}.tar.xz"
)
# Pinned checksum of the official Sparkle release tarball (hashlib, no external tool).
SPARKLE_TARBALL_SHA256 = "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

NOTARY_POLL_INTERVAL = 30
NOTARY_TIMEOUT = 3600
NOTARY_MAX_QUERY_FAILURES = 10

# Machine-local credential file for unattended runs. Plain KEY=VALUE lines,
# mode 600, never committed (same directory convention as the Sparkle seed).
NOTARY_ENV_FILE = Path.home() / ".config" / "textsnap" / "notary.env"
NOTARY_ENV_KEYS = (
    "TEXTSNAP_NOTARY_KEY",
    "TEXTSNAP_NOTARY_KEY_ID",
    "TEXTSNAP_NOTARY_ISSUER",
)


class Failure(Exception):
    """Fatal pipeline error: message is already user-readable."""


def log(msg: str) -> None:
    print(f"[publish] {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"[publish] WARNING: {msg}", flush=True)


def run(argv: list[str], **kwargs) -> subprocess.CompletedProcess:
    kwargs.setdefault("cwd", REPO_ROOT)
    return subprocess.run(argv, **kwargs)


def capture(argv: list[str], **kwargs) -> subprocess.CompletedProcess:
    kwargs.setdefault("cwd", REPO_ROOT)
    kwargs.setdefault("stdout", subprocess.PIPE)
    kwargs.setdefault("stderr", subprocess.STDOUT)
    kwargs.setdefault("text", True)
    return subprocess.run(argv, **kwargs)


def need_tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise Failure(f"missing required tool {name!r} on PATH")
    return path


def read_xcconfig(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("//") or line.startswith("#include"):
            continue
        m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$", line)
        if m:
            values[m.group(1)] = m.group(2).strip()
    return values


def team_id_from_project_yml() -> str:
    text = (REPO_ROOT / "project.yml").read_text(encoding="utf-8")
    m = re.search(r"DEVELOPMENT_TEAM:\s*([A-Z0-9]+)", text)
    if not m:
        raise Failure("DEVELOPMENT_TEAM not found in project.yml")
    return m.group(1)


def guard_no_version_double_write() -> None:
    """project.yml must not re-declare versions; xcconfig is the single source."""
    text = (REPO_ROOT / "project.yml").read_text(encoding="utf-8")
    for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
        if re.search(rf"^\s*{key}\s*:", text, re.MULTILINE):
            raise Failure(
                f"project.yml re-declares {key}; versions live in "
                "Configuration/*.xcconfig only"
            )


# ---------------------------------------------------------------- versions ---


def load_version() -> tuple[str, int]:
    guard_no_version_double_write()
    cfg = read_xcconfig(REPO_ROOT / "Configuration" / "Base.xcconfig")
    marketing = cfg.get("MARKETING_VERSION", "")
    build_raw = cfg.get("CURRENT_PROJECT_VERSION", "")
    if not re.fullmatch(r"\d+\.\d+\.\d+", marketing):
        raise Failure(f"MARKETING_VERSION {marketing!r} is not SemVer x.y.z")
    if not re.fullmatch(r"[1-9][0-9]*", build_raw):
        raise Failure(
            f"CURRENT_PROJECT_VERSION {build_raw!r} must be a strictly "
            "increasing positive integer (Sparkle keys off it)"
        )
    return marketing, int(build_raw)


def tag_for(marketing: str) -> str:
    return f"v{marketing}"


def live_appcast_build() -> int | None:
    """Best-effort anonymous read of the live feed's newest build number."""
    url = f"https://github.com/{GITHUB_SLUG}/releases/latest/download/appcast.xml"
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            body = resp.read().decode("utf-8", "replace")
    except Exception:
        return None
    builds = [
        int(n)
        for n in re.findall(
            r"<sparkle:version>(\d+)</sparkle:version>", body
        )
    ]
    builds += [
        int(n)
        for n in re.findall(
            r'sparkle:version="(\d+)"', body
        )
    ]
    return max(builds) if builds else None


# --------------------------------------------------------------- prechecks ---


def check_signing_identity() -> None:
    out = capture(
        ["security", "find-identity", "-v", "-p", "codesigning"]
    ).stdout
    identities = [
        line for line in out.splitlines() if "Developer ID Application" in line
    ]
    if not identities:
        raise Failure(
            "no 'Developer ID Application' identity in the login keychain.\n"
            "Self-help: Xcode -> Settings -> Accounts -> Manage Certificates -> "
            "+ -> Developer ID Application (Account Holder only; 5 per account)."
        )
    log(f"signing identity: {identities[0].strip()}")


def load_local_notary_env() -> None:
    """Fill missing TEXTSNAP_NOTARY_* vars from the machine-local file.

    Explicit environment variables always win; a missing or unreadable file
    changes nothing (the usual credential errors still fire below).
    Only the three known keys are honored, so stray lines cannot inject
    unrelated environment."""
    try:
        lines = NOTARY_ENV_FILE.read_text(encoding="utf-8").splitlines()
    except OSError:
        return
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key in NOTARY_ENV_KEYS and value:
            os.environ.setdefault(key, value)
    log(f"consulted local notary env {NOTARY_ENV_FILE} (explicit env wins)")


def require_env(name: str, hint: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise Failure(f"missing credential env {name}.\nSelf-help: {hint}")
    return value


def check_notary_creds() -> dict[str, str]:
    key = require_env(
        "TEXTSNAP_NOTARY_KEY",
        "export TEXTSNAP_NOTARY_KEY=<path to the Team Key .p8>  "
        "(App Store Connect -> Users and Access -> Integrations -> Team Keys)",
    )
    key_id = require_env(
        "TEXTSNAP_NOTARY_KEY_ID",
        "export TEXTSNAP_NOTARY_KEY_ID=<Key ID shown next to the .p8 download>",
    )
    issuer = require_env(
        "TEXTSNAP_NOTARY_ISSUER",
        "export TEXTSNAP_NOTARY_ISSUER=<Issuer ID on the same Team Keys page>",
    )
    if not Path(key).is_file():
        raise Failure(
            f"TEXTSNAP_NOTARY_KEY points at {key!r}, which is not a file.\n"
            "Self-help: copy the .p8 to this Mac (it downloads exactly once) "
            "and point the variable at it."
        )
    probe = capture(
        [
            "xcrun", "notarytool", "history",
            "--key", key, "--key-id", key_id, "--issuer", issuer,
            "--output-format", "json",
        ]
    )
    if probe.returncode != 0 or "submission history" not in probe.stdout.lower():
        raise Failure(
            "notarytool could not reach Apple with these credentials "
            f"(exit {probe.returncode}).\n"
            f"Output: {probe.stdout.strip()[:400]}\n"
            "Self-help: re-check Key ID / Issuer ID (must be a *Team* Key, "
            "not an Individual Key), then re-run this script."
        )
    log("notarytool credentials reach Apple")
    return {"key": key, "key_id": key_id, "issuer": issuer}


def check_ed_key() -> Path:
    default = Path.home() / ".config" / "textsnap" / "sparkle-ed25519-seed"
    raw = os.environ.get("TEXTSNAP_SPARKLE_ED_KEY_FILE", str(default)).strip()
    path = Path(raw)
    if not path.is_file():
        raise Failure(
            f"Sparkle EdDSA seed file {str(path)!r} not found.\n"
            "Self-help: generate one Ed25519 seed for this app, keep it off git "
            "(mode 600), and export TEXTSNAP_SPARKLE_ED_KEY_FILE=<that path>. "
            "The matching SUPublicEDKey is already in TextSnap/Info.plist; "
            "rotating it requires a key-change transition update, never a silent swap."
        )
    seed_b64 = path.read_text(encoding="utf-8").strip()
    if len(seed_b64) != 44:
        raise Failure(
            f"Sparkle seed file {str(path)!r} does not look like a base64 "
            "32-byte Ed25519 seed (expected 44 chars)."
        )
    st = path.stat()
    if st.st_mode & 0o077:
        warn(f"{path} is group/world-readable; chmod 600 it")
    return path


def repo_exists() -> bool:
    probe = capture(["gh", "repo", "view", GITHUB_SLUG, "--json", "name"])
    return probe.returncode == 0


def tag_pushed(tag: str) -> bool:
    probe = capture(
        ["git", "ls-remote", f"https://github.com/{GITHUB_SLUG}.git",
         f"refs/tags/{tag}"]
    )
    return probe.returncode == 0 and bool(probe.stdout.strip())


# ------------------------------------------------------------------ build ---


def generate_project() -> None:
    need_tool("xcodegen")
    log("xcodegen generate")
    proc = run(["xcodegen", "generate"])
    if proc.returncode != 0:
        raise Failure("xcodegen generate failed")


def archive_app(workdir: Path, team_id: str) -> tuple[Path, Path]:
    """Route A: archive + exportArchive so nested Sparkle helpers get re-signed."""
    archive = workdir / "TextSnap.xcarchive"
    export_dir = workdir / "export"
    if archive.exists():
        shutil.rmtree(archive)
    if export_dir.exists():
        shutil.rmtree(export_dir)
    export_dir.mkdir(parents=True)

    log("xcodebuild archive (Release)")
    proc = run(
        [
            "xcodebuild", "archive",
            "-project", str(PROJECT),
            "-scheme", SCHEME,
            "-configuration", "Release",
            "-destination", "platform=macOS",
            "-derivedDataPath", str(workdir / "DerivedData"),
            "-archivePath", str(archive),
        ]
    )
    if proc.returncode != 0:
        raise Failure("xcodebuild archive failed")
    apps_dir = archive / "Products" / "Applications"
    shipped = sorted(p for p in apps_dir.glob("*.app") if p.is_dir()) \
        if apps_dir.is_dir() else []
    if len(shipped) != 1:
        raise Failure(
            f"archive ships {len(shipped)} apps under Products/Applications "
            f"(expected exactly 1); usually a helper target without "
            f"SKIP_INSTALL=YES leaked in as an independent product. "
            f"Found: {[p.name for p in shipped]}"
        )

    options = {
        "method": "developer-id",
        "teamID": team_id,
        "signingStyle": "manual",
        "signingCertificate": "Developer ID Application",
    }
    options_path = workdir / "ExportOptions.plist"
    with options_path.open("wb") as fh:
        plistlib.dump(options, fh)

    log("xcodebuild -exportArchive")
    proc = run(
        [
            "xcodebuild", "-exportArchive",
            "-archivePath", str(archive),
            "-exportPath", str(export_dir),
            "-exportOptionsPlist", str(options_path),
        ]
    )
    if proc.returncode != 0:
        raise Failure("xcodebuild -exportArchive failed")
    app = export_dir / f"{APP_NAME}.app"
    if not app.is_dir():
        raise Failure(f"exported app missing at {app}")
    return app, export_dir


def assert_signature(path: Path, what: str) -> None:
    out = capture(["codesign", "-dv", "--verbose=2", str(path)]).stdout
    if "Authority=Developer ID Application" not in out:
        raise Failure(f"{what}: not Developer ID signed:\n{out[:800]}")
    if "Timestamp=" not in out:
        raise Failure(f"{what}: missing secure timestamp (--timestamp):\n{out[:800]}")
    if "flags=" in out and "runtime" not in out.split("flags=")[1].split("\n")[0]:
        raise Failure(f"{what}: hardened runtime flag missing:\n{out[:800]}")


def self_check_signatures(app: Path) -> None:
    log("signature self-checks")
    assert_signature(app, "main app")
    ent = capture(["codesign", "-d", "--entitlements", "-", str(app)]).stdout
    if "get-task-allow" in ent:
        raise Failure(
            "Release entitlements contain com.apple.security.get-task-allow "
            "(CODE_SIGN_INJECT_BASE_ENTITLEMENTS must be NO); Apple would reject this."
        )
    # Nested Sparkle executables must be Developer ID signed too; deep --strict
    # alone cannot see adhoc signatures, so check each one explicitly.
    nested = [
        app / "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater",
        app / "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate",
        app / "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer",
        app / "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader",
    ]
    for item in nested:
        if item.exists():
            assert_signature(item, f"nested {item.name}")
        else:
            warn(f"nested component absent (Sparkle layout changed?): {item}")
    proc = run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])
    if proc.returncode != 0:
        raise Failure("codesign --verify --deep --strict failed")


# ----------------------------------------------------------------- notary ---


def notarize(
    creds: dict[str, str], path: Path, workdir: Path, skip: bool
) -> None:
    if skip:
        warn(f"notarization skipped for {path.name} (--skip-notarize); "
             "output is NOT shippable")
        return
    zippath = workdir / f"{path.stem}-notarize.zip"
    if zippath.exists():
        zippath.unlink()
    log(f"packing {path.name} for notarization")
    proc = run(["ditto", "-c", "-k", "--keepParent", str(path), str(zippath)])
    if proc.returncode != 0:
        raise Failure(f"ditto zip failed for {path}")

    started = datetime.now(timezone.utc)
    log("notarytool submit")
    proc = capture(
        [
            "xcrun", "notarytool", "submit", str(zippath),
            "--key", creds["key"], "--key-id", creds["key_id"],
            "--issuer", creds["issuer"],
            "--output-format", "json",
        ]
    )
    submission_id = ""
    try:
        submission_id = json.loads(proc.stdout or "{}").get("id", "")
    except json.JSONDecodeError:
        submission_id = ""
    if not submission_id:
        # Submit may already have been accepted server-side while the local
        # connection died: claim our submission back by name + start time.
        margin = started.timestamp() - 60
        margin_iso = datetime.fromtimestamp(margin, tz=timezone.utc).isoformat()
        hist = capture(
            [
                "xcrun", "notarytool", "history",
                "--key", creds["key"], "--key-id", creds["key_id"],
                "--issuer", creds["issuer"],
                "--output-format", "json",
            ]
        )
        try:
            entries = json.loads(hist.stdout or "{}").get("history", [])
        except json.JSONDecodeError:
            entries = []
        cands = [
            e for e in entries
            if e.get("name") == zippath.name
            and e.get("createdDate", "") >= margin_iso
        ]
        if cands:
            submission_id = sorted(cands, key=lambda e: e["createdDate"])[-1].get("id", "")
            log(f"claimed submission {submission_id} from history")
    if not submission_id:
        raise Failure(
            f"notarytool submit returned no id for {zippath.name}.\n"
            f"Output: {proc.stdout.strip()[:500]}"
        )

    deadline = time.time() + NOTARY_TIMEOUT
    failures = 0
    while True:
        probe = capture(
            [
                "xcrun", "notarytool", "info", submission_id,
                "--key", creds["key"], "--key-id", creds["key_id"],
                "--issuer", creds["issuer"],
                "--output-format", "json",
            ]
        )
        status = ""
        try:
            status = json.loads(probe.stdout or "{}").get("status", "")
        except json.JSONDecodeError:
            status = ""
        if status in ("Accepted", "Invalid"):
            if status != "Accepted":
                raise Failure(
                    f"Apple notarization {status} for {path.name} "
                    f"(submission {submission_id}). Fetch the log with:\n"
                    f"xcrun notarytool log {submission_id} "
                    f"--key $TEXTSNAP_NOTARY_KEY --key-id $TEXTSNAP_NOTARY_KEY_ID "
                    "--issuer $TEXTSNAP_NOTARY_ISSUER"
                )
            log(f"notarization Accepted for {path.name}")
            break
        if not status:
            failures += 1
            if failures >= NOTARY_MAX_QUERY_FAILURES:
                raise Failure(
                    "notarytool info keeps failing; giving up instead of "
                    f"spinning. Resume with: xcrun notarytool info {submission_id} "
                    "--key $TEXTSNAP_NOTARY_KEY --key-id $TEXTSNAP_NOTARY_KEY_ID "
                    "--issuer $TEXTSNAP_NOTARY_ISSUER"
                )
            warn(f"info query failed ({failures}/{NOTARY_MAX_QUERY_FAILURES}); retrying")
        else:
            log(f"notarization status: {status}; waiting")
        if time.time() > deadline:
            raise Failure(
                f"notarization timed out after {NOTARY_TIMEOUT // 60} min "
                f"(submission {submission_id}); check it by hand, do NOT resubmit blindly."
            )
        time.sleep(NOTARY_POLL_INTERVAL)

    log(f"stapler staple {path.name}")
    proc = run(["xcrun", "stapler", "staple", str(path)])
    if proc.returncode != 0:
        raise Failure(f"stapler staple failed for {path}")


# ------------------------------------------------------------- appcast/zip ---


def fetch_sparkle_tools(workdir: Path) -> Path:
    cache = Path.home() / ".cache" / "textsnap" / f"sparkle-{SPARKLE_VERSION}"
    binary = cache / "bin" / "generate_appcast"
    if binary.is_file():
        return binary
    cache.mkdir(parents=True, exist_ok=True)
    tarball = workdir / f"Sparkle-{SPARKLE_VERSION}.tar.xz"
    log("downloading official Sparkle tools")
    req = urllib.request.Request(
        SPARKLE_TARBALL_URL, headers={"User-Agent": "TextSnap-publish"}
    )
    with urllib.request.urlopen(req, timeout=120) as resp, tarball.open("wb") as fh:
        shutil.copyfileobj(resp, fh)
    digest = hashlib.sha256(tarball.read_bytes()).hexdigest()
    if digest != SPARKLE_TARBALL_SHA256:
        tarball.unlink(missing_ok=True)
        raise Failure(
            f"Sparkle tarball checksum mismatch (got {digest}); refusing to run it."
        )
    proc = run(["tar", "-xf", str(tarball), "-C", str(cache)])
    if proc.returncode != 0 or not binary.is_file():
        raise Failure("unpacking Sparkle tools failed")
    return binary


def build_update_zip_and_appcast(
    app: Path, workdir: Path, marketing: str, build_no: int,
    ed_key_file: Path, tag: str,
) -> tuple[Path, Path]:
    updates = workdir / "updates"
    updates.mkdir(parents=True, exist_ok=True)
    zipname = f"{APP_NAME}-{marketing}.zip"
    zippath = updates / zipname
    if zippath.exists():
        zippath.unlink()
    log(f"re-zipping stapled app -> {zipname} (must postdate stapling)")
    proc = run(["ditto", "-c", "-k", "--keepParent", str(app), str(zippath)])
    if proc.returncode != 0:
        raise Failure("update zip packing failed")

    notes = updates / f"{APP_NAME}-{marketing}.md"
    notes.write_text(
        f"# {APP_NAME} {marketing}\n\n"
        "- Screen-text capture, on-device only.\n"
        "- 屏幕框选识字，仅本机识别。\n",
        encoding="utf-8",
    )
    tool = fetch_sparkle_tools(workdir)
    log("generate_appcast (signed feed + signed archive)")
    proc = run(
        [
            str(tool), str(updates),
            "--ed-key-file", str(ed_key_file),
            "--download-url-prefix",
            f"https://github.com/{GITHUB_SLUG}/releases/download/{tag}/",
            "--embed-release-notes",
        ]
    )
    if proc.returncode != 0:
        raise Failure("generate_appcast failed")
    appcast = updates / "appcast.xml"
    if not appcast.is_file():
        raise Failure("generate_appcast produced no appcast.xml")
    body = appcast.read_text(encoding="utf-8")
    if f"<sparkle:version>{build_no}</sparkle:version>" not in body:
        raise Failure("fresh appcast does not carry the new build number")
    if "edSignature" not in body:
        raise Failure("fresh appcast carries no EdDSA archive signature")
    return zippath, appcast


# -------------------------------------------------------------------- dmg ---


def build_dmg(app: Path, workdir: Path, marketing: str) -> Path:
    dmg = workdir / f"{APP_NAME}-{marketing}.dmg"
    if dmg.exists():
        dmg.unlink()
    stage = Path(tempfile.mkdtemp(prefix="textsnap-dmg-"))
    try:
        log("staging dmg (.app + /Applications symlink)")
        proc = run(["ditto", str(app), str(stage / f"{APP_NAME}.app")])
        if proc.returncode != 0:
            raise Failure("dmg staging ditto failed")
        link = stage / "Applications"
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to("/Applications")
        volname = f"{APP_NAME} {marketing}"
        out = capture(["sw_vers", "-productVersion"]).stdout.strip()
        major = int(out.split(".")[0]) if out[:2].isdigit() else 0
        if major >= 26:
            proc = run(
                [
                    "diskutil", "image", "create", "from", str(stage), str(dmg),
                    "--format", "UDZO", "--volumeName", volname,
                ]
            )
        else:
            proc = run(
                [
                    "hdiutil", "create", "-volname", volname,
                    "-srcfolder", str(stage), "-ov", "-format", "UDZO", str(dmg),
                ]
            )
        if proc.returncode != 0 or not dmg.is_file():
            raise Failure("dmg creation failed")
    finally:
        shutil.rmtree(stage, ignore_errors=True)
    return dmg


def final_gatekeeper_checks(app: Path, dmg: Path, skip_notarized: bool) -> None:
    log("spctl assess stapled app")
    proc = capture(["spctl", "-a", "-vvv", "-t", "install", str(app)])
    combined = proc.stdout
    if proc.returncode != 0 or "accepted" not in combined.lower():
        raise Failure(f"spctl rejected the app:\n{combined[:800]}")
    if skip_notarized:
        warn("skipping stapler validate (notarization was skipped)")
        return
    for target in (app, dmg):
        proc = run(["xcrun", "stapler", "validate", str(target)])
        if proc.returncode != 0:
            raise Failure(f"stapler validate failed for {target.name}")


def dmg_smoke(dmg: Path) -> None:
    """Mount read-only, assert .app + /Applications link, detach. No install."""
    mount = Path(tempfile.mkdtemp(prefix="textsnap-mnt-"))
    os.rmdir(mount)
    log("dmg smoke: attach read-only")
    proc = capture(["hdiutil", "attach", "-readonly", str(dmg),
                    "-mountpoint", str(mount)])
    if proc.returncode != 0:
        raise Failure(f"dmg mount failed:\n{proc.stdout[:500]}")
    try:
        if not (mount / f"{APP_NAME}.app").is_dir():
            raise Failure("mounted dmg has no TextSnap.app")
        if not (mount / "Applications").is_symlink():
            raise Failure("mounted dmg has no /Applications symlink")
        log("dmg smoke ok: .app + /Applications symlink present")
    finally:
        run(["hdiutil", "detach", str(mount)])


# ---------------------------------------------------------------- release ---


def ensure_tag_pushed(tag: str) -> None:
    if capture(["git", "rev-parse", "--verify", f"refs/tags/{tag}"]).returncode != 0:
        log(f"creating local tag {tag} at HEAD")
        if run(["git", "tag", tag]).returncode != 0:
            raise Failure(f"git tag {tag} failed")
    else:
        log(f"local tag {tag} exists; reusing (never moving it)")
    if tag_pushed(tag):
        log(f"tag {tag} already on the server")
        return
    log(f"pushing tag {tag} (one retry)")
    url = f"https://github.com/{GITHUB_SLUG}.git"
    for attempt in (1, 2):
        if run(["git", "push", url, f"refs/tags/{tag}"]).returncode == 0:
            return
        time.sleep(5)
    raise Failure(
        f"git push of tag {tag} failed twice; push it by hand, then re-run "
        "(do NOT rebuild or re-notarize; the产物 is already final)."
    )


def release_exists(tag: str) -> bool:
    return capture(
        ["gh", "release", "view", tag, "-R", GITHUB_SLUG, "--json", "tagName"]
    ).returncode == 0


def create_empty_release(tag: str, marketing: str) -> None:
    log(f"creating empty Release {tag} (attachments follow one by one)")
    for attempt in range(4):
        proc = capture(
            [
                "gh", "release", "create", tag, "-R", GITHUB_SLUG,
                "--title", f"{APP_NAME} {marketing}",
                "--notes", f"{APP_NAME} {marketing} ({marketing}).",
            ]
        )
        if proc.returncode == 0:
            return
        if release_exists(tag):
            log("Release appeared concurrently; continuing")
            return
        warn(f"release create attempt {attempt + 1} failed; retrying")
        time.sleep(5)
    raise Failure(
        f"gh release create {tag} kept failing (Forgejo/GitHub tag-visibility "
        "lag can 404 for a few seconds; wait, then re-run — do NOT rebuild)."
    )


def upload_assets(tag: str, assets: list[Path]) -> list[str]:
    for asset in assets:
        log(f"uploading {asset.name} (--clobber)")
        proc = run(
            ["gh", "release", "upload", tag, str(asset),
             "--clobber", "-R", GITHUB_SLUG]
        )
        if proc.returncode != 0:
            raise Failure(f"upload failed for {asset.name}; re-run to resume")
    probe = capture(
        ["gh", "release", "view", tag, "-R", GITHUB_SLUG,
         "--json", "assets", "--jq", ".assets[].name"]
    )
    present = set(probe.stdout.split())
    missing = [a.name for a in assets if a.name not in present]
    if missing:
        raise Failure(
            f"Release {tag} is missing attachments {missing} after upload; "
            "re-run to resume (uploads are --clobber, notarization is NOT repeated)."
        )
    return sorted(present)


def anonymous_final_check(tag: str, assets: list[Path]) -> None:
    base = f"https://github.com/{GITHUB_SLUG}/releases/download/{tag}"
    latest = f"https://github.com/{GITHUB_SLUG}/releases/latest/download"
    urls = [f"{base}/{a.name}" for a in assets] + [f"{latest}/appcast.xml"]
    for url in urls:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "TextSnap-publish"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                if resp.status != 200:
                    raise Failure(f"anonymous fetch {url} -> HTTP {resp.status}")
                log(f"anonymous fetch ok: {url} ({resp.length or '?'} bytes)")
        except Failure:
            raise
        except Exception as exc:
            raise Failure(f"anonymous fetch failed for {url}: {exc}") from exc


# ------------------------------------------------------------------- main ---


def main() -> int:
    parser = argparse.ArgumentParser(description="TextSnap public-release pipeline")
    parser.add_argument("--local-only", action="store_true",
                        help="build/sign/notarize locally; touch nothing remote")
    parser.add_argument("--skip-notarize", action="store_true",
                        help="skip Apple notarization (output is NOT shippable)")
    parser.add_argument("--workdir", default=str(REPO_ROOT / "build" / "publish"),
                        help="scratch directory for archives and images")
    args = parser.parse_args()

    lockpath = REPO_ROOT / "build" / "publish-release.lock"
    lockpath.parent.mkdir(parents=True, exist_ok=True)
    lockfh = lockpath.open("w")
    try:
        fcntl.flock(lockfh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("[publish] another publish-release run holds the lock; "
              "same worktree must never publish twice concurrently.",
              file=sys.stderr)
        return 1

    try:
        load_local_notary_env()
        for tool in ("xcodebuild", "codesign", "ditto", "hdiutil",
                     "xcrun", "security", "git"):
            need_tool(tool)

        marketing, build_no = load_version()
        tag = tag_for(marketing)
        log(f"version {marketing} (build {build_no}), tag {tag}")
        team_id = team_id_from_project_yml()

        check_signing_identity()
        creds = check_notary_creds()
        ed_key_file = check_ed_key()

        full = not args.local_only
        has_repo = False
        if full:
            need_tool("gh")
            # Keychain-backed gh auth can flap once right after other
            # security/notarytool calls; retry briefly, never prompt.
            authed = False
            for _ in range(3):
                if capture(["gh", "auth", "status"]).returncode == 0:
                    authed = True
                    break
                time.sleep(5)
            if not authed:
                raise Failure(
                    "gh is not authenticated.\nSelf-help: gh auth login"
                )
            has_repo = repo_exists()
            if not has_repo:
                warn(
                    f"public repo {GITHUB_SLUG} does not exist yet: "
                    "build + sign + notarize will run, upload steps are skipped."
                )
            else:
                if not tag_pushed(tag):
                    warn(
                        f"tag {tag} is not on the server yet; it will be "
                        "pushed after the产物 is final (never before signing)."
                    )
                live = live_appcast_build()
                if live is not None and live >= build_no:
                    raise Failure(
                        f"anti-rollback: live feed already serves build {live}, "
                        f"local build is {build_no}; refusing to publish older bits."
                    )
                if live is not None:
                    log(f"anti-rollback ok: live build {live} < local {build_no}")
                else:
                    log("anti-rollback: no live feed readable (first release?)")

        workdir = Path(args.workdir)
        workdir.mkdir(parents=True, exist_ok=True)

        generate_project()
        app, _export_dir = archive_app(workdir, team_id)
        self_check_signatures(app)

        notarize(creds, app, workdir, args.skip_notarize)

        zippath, appcast = build_update_zip_and_appcast(
            app, workdir, marketing, build_no, ed_key_file, tag
        )
        dmg = build_dmg(app, workdir, marketing)
        notarize(creds, dmg, workdir, args.skip_notarize)
        final_gatekeeper_checks(app, dmg, args.skip_notarize)
        dmg_smoke(dmg)

        assets = [dmg, zippath, appcast]
        uploaded: list[str] = []
        if full and has_repo:
            ensure_tag_pushed(tag)
            if not release_exists(tag):
                create_empty_release(tag, marketing)
            else:
                log(f"Release {tag} exists; uploading with --clobber")
            uploaded = upload_assets(tag, assets)
            anonymous_final_check(tag, assets)
        elif full:
            log("upload steps skipped (no public repo); local artifacts are final")

        print()
        print(f"version: {marketing} (build {build_no})")
        print(f"tag: {tag}")
        print(f"dmg: {dmg} ({dmg.stat().st_size} bytes)")
        print(f"update zip: {zippath} ({zippath.stat().st_size} bytes)")
        print(f"appcast: {appcast}")
        print(f"attachments on Release {tag}: "
              f"{len(uploaded)} ({', '.join(uploaded) if uploaded else 'none yet'})")
        print(f"first install: https://github.com/{GITHUB_SLUG}/releases/latest")
        print(f"update feed: https://github.com/{GITHUB_SLUG}"
              "/releases/latest/download/appcast.xml")
        print("done.")
        return 0
    except Failure as exc:
        print(f"[publish] FAILED: {exc}", file=sys.stderr)
        return 1
    finally:
        try:
            fcntl.flock(lockfh, fcntl.LOCK_UN)
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
