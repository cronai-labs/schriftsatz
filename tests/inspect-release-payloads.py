#!/usr/bin/env python3
"""Print `draft target_commitish draft` from goreleaser's two release payloads.

Split out of tests/release-dryrun.sh rather than inlined as a heredoc: a
heredoc inside a $( ) inside a heredoc is exactly the construct that makes a
shell script unreadable and unlintable, and shellcheck cannot see into it.
"""
import json
import sys

create = json.load(open(sys.argv[1], encoding="utf-8"))
update = json.load(open(sys.argv[2], encoding="utf-8"))
print(create.get("draft"), create.get("target_commitish") or "-", update.get("draft"))
