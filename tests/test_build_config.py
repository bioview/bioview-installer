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
    assert len(cfg["packages"]) == 4


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
        "bioview-viewer",
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


# --- One installer, three apps ----------------------------------------------
# The suite ships a single frozen binary; Monitor, Configurator and Viewer are
# the roles it dispatches on. Every packaging target has to offer all three, and
# a recording has to reach the Viewer on every platform -- a .bvr that opens the
# Monitor is worse than one that opens nothing.


def test_every_role_is_declared_with_a_name():
    cfg = _load_build_toml()
    roles = {r["role"]: r for r in cfg["roles"]}
    assert set(roles) == {"monitor", "configurator", "viewer"}
    for role in roles.values():
        assert role["name"] and role["description"]


def test_the_recording_type_is_declared_once_for_every_platform():
    doc = _load_build_toml()["document"]
    assert doc["extension"] == "bvr"
    assert doc["role"] == "viewer"
    assert doc["mime"] == "application/x-bioview-recording"
    assert doc["uti"].startswith("org.bioview.")


def test_the_viewer_package_is_built_from_its_own_repo():
    pkgs = {p["name"]: p for p in _load_build_toml()["packages"]}
    viewer = pkgs["bioview-viewer"]
    assert viewer["git"].startswith("https://github.com/bioview/")
    assert viewer["local"] == "../bioview-viewer"


def test_every_package_is_tagged_at_the_app_version():
    """The Viewer inherits the suite version like the other packages: one tag
    per release, or the builders would clone mismatched sources."""
    cfg = _load_build_toml()
    expected = "v" + cfg["app"]["version"]
    for pkg in cfg["packages"]:
        assert pkg["ref"] == expected, f"{pkg['name']} is pinned to {pkg['ref']}"


def test_windows_installer_offers_all_three_roles_and_the_association():
    iss = (INSTALLER_DIR / "windows" / "setup.iss").read_text()
    for role in ("configurator", "viewer"):
        assert f"--role {role}" in iss, f"no shortcut launches the {role}"
    # A recording must open the Viewer, not the Monitor.
    assert '--role viewer ""%1""' in iss


def test_flatpak_ships_a_launcher_per_role_and_the_mime_package():
    flatpak = INSTALLER_DIR / "flatpak"
    manifest = (flatpak / "org.bioview.BioView.yaml").read_text()

    for name in (
        "org.bioview.BioView.desktop",
        "org.bioview.BioView.Configurator.desktop",
        "org.bioview.BioView.Viewer.desktop",
        "org.bioview.BioView.mime.xml",
    ):
        # Flatpak only exports desktop files prefixed with the app id.
        assert (flatpak / name).exists(), f"{name} is missing"
        assert name in manifest, f"{name} is never installed by the manifest"

    assert "./bioview-viewer" in manifest
    viewer_desktop = (flatpak / "org.bioview.BioView.Viewer.desktop").read_text()
    assert "Exec=bioview --role viewer %f" in viewer_desktop
    doc = _load_build_toml()["document"]
    assert doc["mime"] in viewer_desktop
    assert doc["mime"] in (flatpak / "org.bioview.BioView.mime.xml").read_text()


def test_macos_document_types_name_the_configured_extension():
    import write_doc_types

    keys = write_doc_types.document_keys(_load_build_toml())
    doc = _load_build_toml()["document"]
    assert keys["CFBundleDocumentTypes"][0]["CFBundleTypeExtensions"] == [
        doc["extension"]
    ]
    assert keys["UTExportedTypeDeclarations"][0]["UTTypeIdentifier"] == doc["uti"]
    # Finder delivers a document to a running instance only as an event; an app
    # that forbids a second instance without accepting the event opens blank.
    assert keys["LSMultipleInstancesProhibited"] is False


def test_macos_build_emulates_argv_so_a_document_can_pick_its_role():
    """Without --argv-emulation the Finder's path arrives after Qt starts, too
    late for the launcher to choose the Viewer over the Monitor."""
    build = (INSTALLER_DIR / "scripts" / "build_macos.sh").read_text()
    assert "--argv-emulation" in build
    assert "--collect-submodules bioview_viewer" in build
