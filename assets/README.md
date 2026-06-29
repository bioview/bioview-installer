# BioView packaging assets

Drop the application icons here (referenced by `build.toml` and the build scripts):

- `icon.icns` - macOS app icon (used by the `.app`/`.dmg` build)
- `icon.ico` - Windows icon (used by PyInstaller and the Inno installer)
- `icon.png` - 256x256 PNG (used by the Flatpak desktop entry)

All build scripts degrade gracefully if an icon is missing (the bundle is still
produced, just with the default platform icon).
