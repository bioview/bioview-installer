#!/usr/bin/env python3
"""Teach the macOS app bundle that it owns BioView recordings.

PyInstaller is driven from the command line here rather than from a .spec, and
the command line has no way to add arbitrary Info.plist keys -- so the document
type is written in afterwards. This is the macOS half of the `.bvr` association;
Windows does it with registry keys (``windows/setup.iss``) and Linux with a MIME
package (``flatpak/org.bioview.BioView.mime.xml``).

``CFBundleDocumentTypes`` is what makes Finder hand a double-clicked recording to
this app; ``UTExportedTypeDeclarations`` is what gives the identifier behind it a
definition, without which Launch Services falls back to matching the bare
extension. Both are needed.

Usage: write_doc_types.py <path to .app>
"""

import plistlib
import sys
import tomllib
from pathlib import Path


INSTALLER_DIR = Path(__file__).resolve().parent.parent


def _config() -> dict:
    with open(INSTALLER_DIR / "build.toml", "rb") as fh:
        return tomllib.load(fh)


def document_keys(cfg: dict) -> dict:
    """The Info.plist fragment that declares the recording type."""
    doc = cfg["document"]
    return {
        "CFBundleDocumentTypes": [
            {
                "CFBundleTypeName": doc["description"],
                "CFBundleTypeRole": "Viewer",
                "LSHandlerRank": "Owner",
                "LSItemContentTypes": [doc["uti"]],
                "CFBundleTypeExtensions": [doc["extension"]],
                "CFBundleTypeIconFile": "icon.icns",
            }
        ],
        "UTExportedTypeDeclarations": [
            {
                "UTTypeIdentifier": doc["uti"],
                "UTTypeDescription": doc["description"],
                "UTTypeConformsTo": ["public.data", "public.content"],
                "UTTypeIconFile": "icon.icns",
                "UTTypeTagSpecification": {
                    "public.filename-extension": [doc["extension"]],
                    "public.mime-type": [doc["mime"]],
                },
            }
        ],
        # Without this a double-clicked recording opens the app but the path is
        # never delivered: macOS launches a fresh instance instead of sending an
        # open-document event to the one already running.
        "LSMultipleInstancesProhibited": False,
        "NSHighResolutionCapable": True,
    }


def update(app_bundle: Path) -> Path:
    cfg = _config()
    plist_path = app_bundle / "Contents" / "Info.plist"
    if not plist_path.is_file():
        raise SystemExit(f"no Info.plist in {app_bundle}")

    with open(plist_path, "rb") as fh:
        plist = plistlib.load(fh)

    plist.update(document_keys(cfg))
    plist.setdefault("CFBundleShortVersionString", cfg["app"]["version"])
    plist["CFBundleVersion"] = cfg["app"]["version"]

    with open(plist_path, "wb") as fh:
        plistlib.dump(plist, fh)
    return plist_path


def main(argv) -> int:
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2

    cfg = _config()
    plist_path = update(Path(argv[0]))
    print(f"registered .{cfg['document']['extension']} in {plist_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
