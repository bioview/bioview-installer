#!/usr/bin/env python3
"""Tiny accessor for build.toml so the shell/PowerShell builders share one config.

Usage:
    buildcfg.py get app.version          -> prints a single value
    buildcfg.py packages                 -> prints "name|git|ref|local" per package
"""
import sys
from pathlib import Path

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore

CONFIG = Path(__file__).resolve().parent.parent / "build.toml"


def load() -> dict:
    with open(CONFIG, "rb") as fh:
        return tomllib.load(fh)


def get(dotted: str):
    node = load()
    for part in dotted.split("."):
        node = node[part]
    return node


def packages() -> None:
    for pkg in load().get("packages", []):
        print("{name}|{git}|{ref}|{local}".format(
            name=pkg.get("name", ""),
            git=pkg.get("git", ""),
            ref=pkg.get("ref", ""),
            local=pkg.get("local", ""),
        ))


def main(argv) -> int:
    if not argv:
        print("usage: buildcfg.py get <dotted.key> | packages", file=sys.stderr)
        return 2

    cmd = argv[0]
    if cmd == "get" and len(argv) == 2:
        print(get(argv[1]))
        return 0
    if cmd == "packages":
        packages()
        return 0

    print(f"unknown command: {argv}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
