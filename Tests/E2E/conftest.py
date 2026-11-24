"""Pytest configuration for TextSnap background E2E tests."""

from __future__ import annotations

import pathlib
import sys

import pytest
from PIL import Image, ImageDraw, ImageFont

TOOLKIT = pathlib.Path.home() / ".macos-e2e-toolkit"
sys.path.insert(0, str(TOOLKIT / "harness"))
pytest_plugins = ["macos_e2e_harness.pytest_support"]

EXPECTED_TOKENS = ["TextSnap", "E2E", "测试", "2026"]


def _render_fixture_png(destination: pathlib.Path) -> pathlib.Path:
    """Render a crisp 512x256 bilingual PNG fixture with English and Chinese text."""
    width, height = 512, 256
    img = Image.new("RGB", (width, height), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    font_candidates = [
        pathlib.Path("/System/Library/Fonts/PingFang.ttc"),
        pathlib.Path("/System/Library/Fonts/STHeiti Medium.ttc"),
        pathlib.Path("/System/Library/Fonts/Hiragino Sans GB.ttc"),
    ]
    font_path = next((p for p in font_candidates if p.exists()), None)
    font = ImageFont.truetype(str(font_path), 36) if font_path else ImageFont.load_default()
    draw.text((40, 104), "TextSnap E2E 测试 2026", fill=(12, 12, 12), font=font)
    img.save(destination, format="PNG")
    return destination


@pytest.fixture(scope="session")
def e2e_root(tmp_path_factory: pytest.TempPathFactory) -> pathlib.Path:
    return tmp_path_factory.mktemp("textsnap-e2e-root")


@pytest.fixture(scope="session")
def e2e_fixture_png(tmp_path_factory: pytest.TempPathFactory) -> pathlib.Path:
    fixture_dir = tmp_path_factory.mktemp("textsnap-e2e-fixture")
    return _render_fixture_png(fixture_dir / "ocr-fixture.png")


@pytest.fixture(scope="session")
def e2e_expected_tokens() -> list[str]:
    return list(EXPECTED_TOKENS)


@pytest.fixture(scope="session")
def e2e_config(e2e_root: pathlib.Path, e2e_fixture_png: pathlib.Path) -> dict:
    from macos_e2e_harness.pytest_support import load_config

    cfg = load_config()
    args = list(cfg.get("launch_args") or [])
    args.extend([
        "--e2e-root",
        str(e2e_root),
        "--e2e-capture-image",
        str(e2e_fixture_png),
    ])
    cfg["launch_args"] = args
    return cfg
