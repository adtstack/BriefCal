#!/usr/bin/env python3
"""Fail when the app target's xccov line coverage drops below a floor."""

import json
import pathlib
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: check_coverage.py <xccov-report.json> <minimum-fraction>",
            file=sys.stderr,
        )
        return 2

    report_path = pathlib.Path(sys.argv[1])
    minimum = float(sys.argv[2])
    if not 0 <= minimum <= 1:
        print("minimum coverage must be between 0 and 1", file=sys.stderr)
        return 2

    with report_path.open(encoding="utf-8") as report_file:
        report = json.load(report_file)

    targets = [
        target
        for target in report.get("targets", [])
        if target.get("name") == "KaosCal.app"
    ]
    if len(targets) != 1:
        print(
            f"expected exactly one KaosCal.app coverage target; found {len(targets)}",
            file=sys.stderr,
        )
        return 2

    target = targets[0]
    covered = int(target.get("coveredLines", 0))
    executable = int(target.get("executableLines", 0))
    coverage = float(target.get("lineCoverage", 0))
    print(
        f"KaosCal.app line coverage: {coverage:.2%} "
        f"({covered}/{executable}); required: {minimum:.2%}"
    )
    if coverage + 1e-12 < minimum:
        print("coverage floor not met", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
