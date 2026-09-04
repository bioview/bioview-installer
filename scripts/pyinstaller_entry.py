"""Frozen-binary entry point: hands off to ``bioview_client.launch:main``.

That dispatches on ``--role`` (monitor, configurator, or the child server the
GUI roles spawn by re-execing this same binary).
"""
import multiprocessing
import os
import sys


def _configure_bundled_uhd() -> None:
    """Point UHD at the FPGA/firmware images shipped inside the bundle so USRPs
    work without any external UHD installation."""
    if not getattr(sys, "frozen", False):
        return
    base = getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))
    images = os.path.join(base, "share", "uhd", "images")
    if os.path.isdir(images):
        os.environ.setdefault("UHD_IMAGES_DIR", images)


if __name__ == "__main__":
    # Must be first: keeps the frozen app from re-running the GUI when it spawns
    # the child server process.
    multiprocessing.freeze_support()
    _configure_bundled_uhd()

    from bioview_client.launch import main

    sys.exit(main())
