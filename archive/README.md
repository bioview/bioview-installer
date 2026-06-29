# Archived legacy installer scripts

These files are kept for reference only and are no longer part of the build.
They were a mix of two incomplete, mutually inconsistent approaches (a native
`.deb`/`.rpm` path that relied on system Python + system UHD, and an earlier
PyInstaller path referencing a non-existent `build_config.json`).

They are superseded by the three self-contained packaging targets in the parent
directory (Flatpak, macOS `.dmg`, Windows Inno `.exe`), driven by `build.toml`
and `scripts/`.
