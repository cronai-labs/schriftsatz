#!/usr/bin/env python3
"""Exit 0 if the versions given are in strictly ascending SemVer 2.0 order.

Precedence per §11: a pre-release sorts BELOW its normal version, and build
metadata (+sha) is ignored entirely. That second rule is why a dev version needs
the commit counter to order at all.

Exists because scripts/version.sh shipped dev versions that sorted BELOW the
release they followed, and nothing noticed — the drift test compared strings.
"""
import sys


def key(v):
    core = v.split("+", 1)[0]                 # build metadata: ignored
    base, _, pre = core.partition("-")
    nums = tuple(int(x) for x in base.split("."))
    if not pre:
        return (nums, 1, ())
    # Numeric identifiers compare numerically and sort below alphanumeric ones.
    parts = tuple((0, int(p), "") if p.isdigit() else (1, 0, p) for p in pre.split("."))
    return (nums, 0, parts)


vs = sys.argv[1:]
for a, b in zip(vs, vs[1:]):
    if not key(a) < key(b):
        print(f"not ascending: {a} !< {b}", file=sys.stderr)
        sys.exit(1)
print(" < ".join(vs))
