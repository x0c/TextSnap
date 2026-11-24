"""Reusable background, focus-safe E2E tests for TextSnap."""

from __future__ import annotations

import json
import pathlib
import stat
import time

import pytest

from macos_e2e_harness.errors import ElementNotFound


def _wait_for_non_empty_result(driver, expected_tokens: list[str], timeout: float = 90.0) -> str:
    deadline = time.monotonic() + timeout
    last_snapshot = ""
    while time.monotonic() < deadline:
        try:
            text = driver.value("settings.lastResult.text")
            if isinstance(text, str) and text.strip():
                if all(tok in text for tok in expected_tokens):
                    return text
                last_snapshot = text
        except ElementNotFound:
            pass
        joined = driver.text()
        if all(tok in joined for tok in expected_tokens):
            return joined
        time.sleep(0.3)
    raise AssertionError(
        f"Timed out waiting for OCR result containing {expected_tokens}; last={last_snapshot!r}"
    )


def _read_checkbox_value(driver, identifier: str) -> int:
    el = driver.ax().find(identifier=identifier)
    raw = el.value
    if raw is None:
        raw = driver.value(identifier)
    return int(raw)


def test_background_launch_and_initial_baseline(app, driver, vision):
    window = app.window
    assert window.is_on_screen, "E2E Settings window must stay on-screen behind active apps"
    assert round(window.width) == 480

    for ident in (
        "settings.hotkey.button",
        "settings.capture.now",
        "settings.lastResult.empty",
        "settings.launchAtLogin.toggle",
        "settings.menuBar.showIcon",
        "settings.quit.button",
    ):
        driver.locate(identifier=ident)

    shot = vision.stable_shot("settings-initial")
    assert shot.scale_x == pytest.approx(2.0, abs=0.01)
    assert shot.scale_y == pytest.approx(2.0, abs=0.01)

    result = vision.assert_visual("settings-initial", shot=shot, max_diff_ratio=0.0)
    assert result.passed, result.paths
    assert result.status in {"baseline_created", "match"}


def test_capture_now_runs_vision_ocr_and_populates_last_result(
    app, driver, e2e_expected_tokens
):
    located = driver.press(identifier="settings.capture.now")
    assert located.token, "Expected AX element token for settings.capture.now"

    recognized = _wait_for_non_empty_result(driver, e2e_expected_tokens, timeout=90.0)
    for token in e2e_expected_tokens:
        assert token in recognized, f"Missing expected OCR token {token!r} in {recognized!r}"

    driver.locate(identifier="settings.lastResult.copyAgain")
    copy_located = driver.press(identifier="settings.lastResult.copyAgain")
    assert copy_located.token


def test_observability_log_is_secured_and_privacy_safe(
    e2e_root: pathlib.Path, e2e_expected_tokens: list[str]
):
    logs_dir = e2e_root / "logs"
    log_file = logs_dir / "textsnap.log"

    # Wait briefly for async file logger flush.
    deadline = time.monotonic() + 5.0
    content = ""
    while time.monotonic() < deadline:
        if log_file.exists():
            content = log_file.read_text(encoding="utf-8")
            if "copied last result again" in content:
                break
        time.sleep(0.1)

    assert logs_dir.is_dir()
    assert stat.S_IMODE(logs_dir.stat().st_mode) == 0o700
    assert log_file.is_file()
    assert stat.S_IMODE(log_file.stat().st_mode) == 0o600

    for marker in ("app_start", "capture requested", "ocr ok", "device=", "chars=", "copied last result again"):
        assert marker in content, f"Missing log marker {marker!r} in {log_file}"

    # Privacy invariant: recognized text must never appear in diagnostic logs.
    for forbidden in ("TextSnap E2E", "测试"):
        assert forbidden not in content, f"Recognized text {forbidden!r} leaked into {log_file}"


def test_menu_bar_visibility_toggle_persists_in_isolated_root(
    app, driver, e2e_root: pathlib.Path
):
    settings_file = e2e_root / "settings.json"
    initial_val = _read_checkbox_value(driver, "settings.menuBar.showIcon")
    assert initial_val == 1

    driver.press(identifier="settings.menuBar.showIcon")
    deadline = time.monotonic() + 5.0
    data = {}
    while time.monotonic() < deadline:
        if settings_file.exists():
            data = json.loads(settings_file.read_text(encoding="utf-8"))
            if data.get("menuBar.iconVisible") is False:
                break
        time.sleep(0.1)

    assert stat.S_IMODE(e2e_root.stat().st_mode) == 0o700
    assert stat.S_IMODE(settings_file.stat().st_mode) == 0o600
    assert data.get("menuBar.iconVisible") is False

    driver.press(identifier="settings.menuBar.showIcon")
    deadline = time.monotonic() + 5.0
    while time.monotonic() < deadline:
        data = json.loads(settings_file.read_text(encoding="utf-8"))
        if data.get("menuBar.iconVisible") is True:
            break
        time.sleep(0.1)
    assert data.get("menuBar.iconVisible") is True
