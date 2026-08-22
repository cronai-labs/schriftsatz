#!/usr/bin/env python3
"""Print the version git-cliff --context computed, without a leading v.

Reads git-cliff's JSON context on stdin. Prints nothing when there is nothing
to bump, which the caller treats as "no release here".

Split out of tests/release-dryrun.sh rather than inlined: a python heredoc
inside a $( ) inside a shell script is exactly the construct shellcheck cannot
see into, and this one decides a version number.
"""
import json
import sys

context = json.load(sys.stdin)
print(context[0]["version"].lstrip("v") if context else "")
