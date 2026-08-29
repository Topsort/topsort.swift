"""Read an xccov JSON report, enforce a minimum, and write shields.io endpoint-badge JSON.

    coverage.py REPORT --min PERCENT --badge OUT

Only the library targets count; test bundles are excluded. Without a usable report a grey
"unknown" badge is written and the minimum check fails.
"""
import argparse
import json
import sys

LIBRARY_TARGETS = {"Topsort", "TopsortBanners"}

parser = argparse.ArgumentParser()
parser.add_argument("report")
parser.add_argument("--min", type=float)
parser.add_argument("--badge", required=True)
args = parser.parse_args()

badge = {"schemaVersion": 1, "label": "coverage", "message": "unknown", "color": "lightgrey"}
percent = None
try:
    targets = [t for t in json.load(open(args.report))["targets"] if t["name"] in LIBRARY_TARGETS]
    missing = LIBRARY_TARGETS - {t["name"] for t in targets}
    if missing:
        raise ValueError(f"report has no coverage for {sorted(missing)}")
    covered = sum(t["coveredLines"] for t in targets)
    total = sum(t["executableLines"] for t in targets)
    percent = 100 * covered / total
    for t in targets:
        print(f"{t['name']}: {100 * t['lineCoverage']:.1f}% ({t['coveredLines']}/{t['executableLines']})")
    print(f"library lines: {percent:.1f}% ({covered}/{total})")
    shown = round(percent)
    badge.update(message=f"{shown}%", color="brightgreen" if args.min is None or percent >= args.min else "orange")
except (OSError, KeyError, ValueError, ZeroDivisionError) as e:
    print(f"no usable report ({e})", file=sys.stderr)

with open(args.badge, "w") as f:
    json.dump(badge, f)

if args.min is not None:
    if percent is None:
        sys.exit("no coverage number to check against the minimum")
    if percent < args.min:
        sys.exit(f"coverage {percent:.1f}% is below the minimum {args.min:.0f}%")
