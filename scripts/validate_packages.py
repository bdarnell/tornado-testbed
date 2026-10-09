#!/usr/bin/env python3
"""Validate the per-package definitions under packages/.

Run with no arguments for structural checks only (fast, offline). Pass
--check-refs to also confirm each derived git tag resolves upstream, which is
what catches a dependabot version bump whose tag does not exist -- on the bump's
own pull request, rather than during a release build.

    python3 scripts/validate_packages.py
    python3 scripts/validate_packages.py --check-refs
    python3 scripts/validate_packages.py --print-refs

Exits non-zero if anything is wrong.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

# pkglib lives beside this script; importable however this file is invoked.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import pkglib  # noqa: E402


DEPENDABOT_CONFIG = pkglib.ROOT / ".github" / "dependabot.yml"

# A `directories:` entry under packages/, quoted or not. Line-based rather than
# a YAML parse so this stays dependency-free; the file is ours and simple.
DEPENDABOT_DIR_RE = re.compile(r"""^\s*-\s*["']?/packages/(?P<rest>[^"'\s]*)["']?\s*$""")


def check_dependabot(packages: list[pkglib.Package]) -> list[str]:
    """Check dependabot.yml lists exactly the package directories, by name.

    Not a glob: with "/packages/*" dependabot opened every bump twice (see the
    comment in dependabot.yml). An explicit list needs this check so a new
    package is not silently left without updates.
    """
    if not DEPENDABOT_CONFIG.is_file():
        # The harness tests build throwaway roots without .github/.
        return []
    listed: list[str] = []
    problems: list[str] = []
    for line in DEPENDABOT_CONFIG.read_text().splitlines():
        match = DEPENDABOT_DIR_RE.match(line)
        if not match:
            continue
        rest = match.group("rest").rstrip("/")
        if not pkglib.NAME_RE.match(rest):
            problems.append(
                f"dependabot.yml: '/packages/{rest}' is not a single package "
                "directory; list each one explicitly (a glob opens duplicate PRs)"
            )
            continue
        listed.append(rest)
    names = {pkg.name for pkg in packages}
    for name in sorted(names - set(listed)):
        problems.append(f"dependabot.yml: /packages/{name} is missing from directories:")
    for name in sorted(set(listed) - names):
        problems.append(f"dependabot.yml: /packages/{name} is listed but no such package exists")
    for name in sorted({n for n in listed if listed.count(n) > 1}):
        problems.append(f"dependabot.yml: /packages/{name} is listed more than once")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check-refs",
        action="store_true",
        help="also confirm each derived tag resolves in its upstream repo (needs network)",
    )
    parser.add_argument(
        "--print-refs",
        action="store_true",
        help="print the resolved pin and derived ref for each package and exit",
    )
    args = parser.parse_args()

    # Loading is itself most of the validation: pkglib rejects unknown and
    # missing keys, a tag_template without
    # {version}, and a requirements.txt that is not exactly one name==version.
    try:
        packages = pkglib.load_all()
    except pkglib.PackageError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if not packages:
        print("error: no packages found under packages/", file=sys.stderr)
        return 1

    if args.print_refs:
        for pkg in packages:
            print(f"{pkg.name} -> {pkg.dist_name}=={pkg.version} -> {pkg.ref}")
        return 0

    problems: list[str] = []
    for pkg in packages:
        problems.extend(pkglib.check_files(pkg))
    problems.extend(check_dependabot(packages))

    if args.check_refs:
        for pkg in packages:
            message = pkglib.check_ref_exists(pkg)
            if message:
                problems.append(message)

    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)

    print(
        f"checked {len(packages)} package(s): "
        f"{'OK' if not problems else f'{len(problems)} problem(s)'}",
        file=sys.stderr if problems else sys.stdout,
    )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
