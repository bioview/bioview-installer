"""Sanity tests for the installer build configuration and assets.

Every packaging target must reference an icon that exists, and the Flatpak
runtime's Python version must match what the packages require.
"""
import sys
import tomllib
from pathlib import Path

import pytest

INSTALLER_DIR = Path(__file__).resolve().parent.parent
ASSETS = INSTALLER_DIR / "assets"

sys.path.insert(0, str(INSTALLER_DIR / "scripts"))


def _load_build_toml():
    with open(INSTALLER_DIR / "build.toml", "rb") as f:
        return tomllib.load(f)


def test_build_toml_parses_and_has_core_sections():
    cfg = _load_build_toml()
    assert cfg["app"]["name"] == "BioView"
    assert cfg["app"]["app_id"] == "org.bioview.BioView"
    assert "version" in cfg["app"]
    assert cfg["entry"]["module"] == "bioview_client.launch"
    assert len(cfg["packages"]) == 3


def test_all_declared_asset_icons_exist():
    cfg = _load_build_toml()
    for key, rel in cfg["assets"].items():
        path = INSTALLER_DIR / rel
        assert path.exists(), f"assets.{key} -> {rel} is missing"
        assert path.stat().st_size > 0, f"assets.{key} -> {rel} is empty"


def test_source_svgs_present():
    assert (ASSETS / "favicon.svg").exists()
    assert (ASSETS / "favicon_text.svg").exists()


def test_flatpak_icon_png_exists():
    # The Flatpak build hard-fails (unlike macOS/Windows) if this file is absent.
    assert (ASSETS / "icon.png").exists()


def test_flatpak_manifest_uses_supported_runtime_and_icon():
    manifest = (INSTALLER_DIR / "flatpak" / "org.bioview.BioView.yaml").read_text()
    # Freedesktop 24.08 ships Python 3.12, which satisfies requires-python.
    assert "runtime-version: '24.08'" in manifest
    # The manifest installs the app icon it declares as a source.
    assert "../assets/icon.png" in manifest


def test_windows_installer_uses_wordmark_icon():
    cfg = _load_build_toml()
    assert cfg["assets"]["installer_ico"].endswith("installer.ico")
    iss = (INSTALLER_DIR / "windows" / "setup.iss").read_text()
    assert "SetupIconFile" in iss


def test_buildcfg_accessor():
    import buildcfg

    assert buildcfg.get("app.name") == "BioView"
    assert buildcfg.get("assets.icon_png").endswith("icon.png")
    pkgs = buildcfg.load()["packages"]
    assert {p["name"] for p in pkgs} == {
        "bioview-common",
        "bioview-server",
        "bioview-client",
    }


def test_icon_ico_is_valid_ico():
    # The generated .ico must start with the ICONDIR header (reserved=0, type=1).
    data = (ASSETS / "icon.ico").read_bytes()
    assert data[:4] == b"\x00\x00\x01\x00"


@pytest.mark.parametrize("svg", ["favicon.svg", "favicon_text.svg"])
def test_generate_icons_importable_and_ico_builder(svg, tmp_path):
    import generate_icons

    # The pure-Python ICO packer should produce a valid multi-size .ico.
    tiny_png = (ASSETS / "icon.png").read_bytes()  # reuse a real PNG as a stand-in
    out = tmp_path / "out.ico"
    generate_icons.build_ico({16: tiny_png, 32: tiny_png}, out)
    assert out.read_bytes()[:4] == b"\x00\x00\x01\x00"
