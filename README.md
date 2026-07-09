# BioView Installer Builder

Build configurations that package BioView into one self-contained installer per
operating system:

| OS      | Format            | Tooling                          |
| ------- | ----------------- | -------------------------------- |
| Linux   | `.flatpak`        | flatpak-builder                  |
| macOS   | `.dmg`            | PyInstaller + hdiutil            |
| Windows | `.exe` (Setup)    | PyInstaller + Inno Setup         |

Everything is driven by a single config file, [`build.toml`](build.toml), read by
[`scripts/buildcfg.py`](scripts/buildcfg.py).

## What gets bundled

BioView is three Python packages: `bioview-common`, `bioview-server`,
`bioview-client`. The installers bundle all of them plus every Python/Qt
dependency. The frozen app is a single multi-call binary whose behaviour is
selected with `--role`:

- (default) `launcher` - starts a hidden localhost server in a *separate process*
  (so UHD and PyQt never share one interpreter/GIL), then opens the Monitor GUI.
- `server` - the headless server (also what the launcher spawns as its child).
- `monitor` / `configurator` - the individual GUIs.

### UHD (USRP driver) - hybrid delivery

UHD is pinned in `build.toml` (currently **4.10.0.0**) and obtained per platform at
build time:

- **Windows:** `pip install uhd` (official wheel ships libuhd DLLs, bindings, and FPGA images).
- **macOS:** UHD 4.10 is **built from source** against Homebrew Boost/libusb and
  `python@3.13`; native dylibs are staged beside the `uhd` Python package for PyInstaller.
- **Linux:** the Flatpak manifest builds libusb + Boost + UHD (with the Python API) from source.

The USRP backend import is guarded in the server, so the app still runs
(with the dummy backend) when UHD is unavailable.

### Config file association

BioView configuration files use the `.bvi` extension (JSON payload). The
Windows installer registers `.bvi` to open with BioView and forwards the file
path to the monitor via `--config-file`.

## Layout

```
build.toml                         # single source of truth (version, repos, uhd, assets)
assets/                            # icon.icns / icon.ico / icon.png
scripts/
  buildcfg.py                      # reads build.toml for the shell/ps1 builders
  prepare_env.sh / prepare_env.ps1 # clone the 3 repos + build a venv with all deps
  pyinstaller_entry.py             # frozen-binary entry (-> bioview_client.launch:main)
  build_macos.sh                   # .app + .dmg
  build_windows.ps1                # PyInstaller + Inno Setup
flatpak/
  org.bioview.BioView.yaml         # Flatpak manifest (libusb + Boost + UHD + deps)
  org.bioview.BioView.desktop
  org.bioview.BioView.metainfo.xml
windows/setup.iss                  # Inno Setup script (parametrized via /D defines)
.github/workflows/release.yml      # CI matrix; builds + attaches all artifacts on tag
```

The builders prefer a local sibling checkout of each package (`../bioview-*`,
great for development) and fall back to a shallow `git clone` of the pinned ref
when the local path is absent (CI runners). Update the git URLs/refs in
`build.toml` to match your actual repositories.

## Building locally

```bash
# macOS
bash scripts/build_macos.sh            # -> dist/BioView-<version>-<arch>.dmg

# Linux
cd flatpak
flatpak-builder --user --force-clean --repo=repo build org.bioview.BioView.yaml
flatpak build-bundle repo ../dist/BioView.flatpak org.bioview.BioView
```

```powershell
# Windows (needs Inno Setup 6)
./scripts/build_windows.ps1            # -> dist\BioView-<version>-Setup.exe
```

## Building in CI

[`.github/workflows/release.yml`](.github/workflows/release.yml) runs the three
builders on their native runners when a `v*` tag is pushed and attaches the
`.flatpak`, `.dmg` (arm64 + x86_64) and `.exe` artifacts to the GitHub Release.

## Known limitations

- Bundles are large (Qt + UHD + FPGA images).
- macOS builds compile UHD 4.10 from source (~10 min per arch) and are unsigned by
  default (Gatekeeper warns) unless an Apple Developer ID is provided via
  `CODESIGN_IDENTITY`; there is no macOS PyPI wheel for UHD.
- Windows USB USRPs may still need a one-time WinUSB driver (Zadig/UHD installer);
  unsigned installers trigger SmartScreen.
- Flatpak USB access depends on `--device=all`; the from-source UHD/Boost build is
  the slowest, most fragile part of the pipeline.
- UHD bindings, `libuhd`, and FPGA images must all match the single pinned UHD
  version per release.
