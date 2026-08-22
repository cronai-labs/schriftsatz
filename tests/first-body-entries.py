#!/usr/bin/env python3
"""Count list entries in the first release-update payload that carries a body.

A resumed goreleaser run PATCHes the release twice: once with the notes, once
to flip draft:false. Only the first carries a body, so reading the last record
would always report zero and the assertion would pass vacuously.

Split out of tests/release-dryrun.sh rather than inlined: a python heredoc
inside a $( ) inside a shell script is exactly the construct shellcheck cannot
see into.
"""
import json
import sys

for line in open(sys.argv[1], encoding="utf-8"):
    body = json.loads(line).get("body")
    if body:
        print(sum(1 for l in body.splitlines() if l.startswith("- ")))
        break
else:
    print(0)
