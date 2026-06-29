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

UHD is a compiled, version-locked library, so it is obtained per platform at
build time and bundled into the package (pinned in `build.toml`):

- Windows: `pip install uhd` (the official wheel ships libuhd DLLs + bindings + FPGA images).
- macOS: `brew install uhd`; PyInstaller collects the bindings and we add `libuhd.dylib` + the UHD image files into the `.app`.
- Linux: the Flatpak manifest builds libusb + Boost + UHD (with the Python API) from source inside the sandbox.

The USRP backend import is already guarded in the server, so the app still runs
(with the dummy backend) on machines where UHD is unavailable.

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
archive/                           # superseded legacy scripts (deb/rpm/old build_*)
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
- macOS builds are per-arch and unsigned by default (Gatekeeper warns) unless an
  Apple Developer ID is provided via `CODESIGN_IDENTITY`; UHD has no macOS pip
  wheel, so macOS must be built on macOS.
- Windows USB USRPs may still need a one-time WinUSB driver (Zadig/UHD installer);
  unsigned installers trigger SmartScreen.
- Flatpak USB access depends on `--device=all`; the from-source UHD/Boost build is
  the slowest, most fragile part of the pipeline.
- UHD bindings, `libuhd`, and FPGA images must all match the single pinned UHD
  version per release.
