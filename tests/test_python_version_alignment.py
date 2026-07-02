"""Verify the three BioView packages agree on a single tested Python range.

The macOS installer builds all three packages into one shared virtualenv, so
their ``requires-python`` constraints must intersect on a real version (they did
not before: bioview-common allowed 3.14+ while client/server capped at <3.14).

When the sibling package checkouts are not present (e.g. the installer repo is
built standalone in CI), the relevant checks are skipped rather than failing.
"""
import tomllib
from pathlib import Path

import pytest

INSTALLER_DIR = Path(__file__).resolve().parent.parent
MONOREPO_ROOT = INSTALLER_DIR.parent

PACKAGES = ["bioview-common", "bioview-server", "bioview-client"]


def _requires_python(pkg: str):
    pyproject = MONOREPO_ROOT / pkg / "pyproject.toml"
    if not pyproject.exists():
        return None
    with open(pyproject, "rb") as f:
        data = tomllib.load(f)
    return data.get("project", {}).get("requires-python")


@pytest.mark.parametrize("pkg", PACKAGES)
def test_each_package_targets_312_not_314(pkg):
    constraint = _requires_python(pkg)
    if constraint is None:
        pytest.skip(f"{pkg} checkout not present")
    normalized = constraint.replace(" ", "")
    assert ">=3.12" in normalized, f"{pkg} must support Python 3.12: {constraint}"
    assert "<3.14" in normalized, (
        f"{pkg} must cap Python below 3.14 to match the tested combo: {constraint}"
    )


def test_all_present_packages_share_the_same_constraint():
    constraints = {
        pkg: _requires_python(pkg)
        for pkg in PACKAGES
        if _requires_python(pkg) is not None
    }
    if len(constraints) < 2:
        pytest.skip("need at least two package checkouts to compare")
    normalized = {c.replace(" ", "") for c in constraints.values()}
    assert len(normalized) == 1, f"packages disagree on requires-python: {constraints}"
