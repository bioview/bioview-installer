# BioView packaging assets

Branding for every installer target is derived from two source SVGs kept here:

- `favicon.svg` - the app mark (no text). Source for the **application** icon.
- `favicon_text.svg` - the app mark + "BIO VIEW" wordmark. Source for the
  **installer** bundle icon.

## Generated icons

Run `python3 scripts/generate_icons.py` (needs `rsvg-convert`; `.icns` also needs
macOS `iconutil`) to regenerate these from the SVGs:

- `icon.png` - 256x256 app icon (Flatpak desktop entry / Linux hicolor).
- `icon-512.png` - 512x512 app icon (high-DPI / convenience).
- `icon.ico` - multi-size app icon (Windows `.exe` / PyInstaller).
- `icon.icns` - app icon (macOS `.app`).
- `installer.png` / `installer.ico` - installer bundle icon (Inno Setup `.exe`).

`build.toml` maps these paths (`[assets]`) and the build scripts consume them:
the macOS/Windows app bundles use the app icon (`icon.icns` / `icon.ico`), the
Windows Inno Setup installer uses `installer.ico`, and the Flatpak uses
`icon.png`. The macOS and Windows *app* builds degrade gracefully if an icon is
missing, but the **Flatpak build requires `icon.png`**.
