# schriftsatz — one frontend. CI runs these same targets.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# Single source of truth: the git tag, read by exactly one thing.
#
# It used to be the newest heading in CHANGELOG.md, which made the version a
# TRACKED FILE — and a tracked file only changes on main through a pull request,
# so cutting a release required one. That ceremony was a consequence of where
# the version lived, not a policy. See #30.
#
# `:=` and not `?=`: `?=` would let a stray VERSION in the environment win
# silently, and would re-fork the script on every reference. An explicit
# `make bin VERSION=...` still overrides `:=`, which is what the drift test's
# negative control relies on.
VERSION := $(shell ./scripts/version.sh)
BIN     := build/schriftsatz
LDFLAGS := -s -w -X main.version=$(VERSION)

.PHONY: help setup check test test-fast lint fmt bin build run clean changelog release release-dryrun version next

help: ## List targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-10s\033[0m %s\n", $$1, $$2}'

setup: ## Verify the toolchain (installs nothing globally)
	@missing=0; \
	for t in pandoc xelatex; do \
	  command -v $$t >/dev/null || { echo "missing: $$t"; missing=1; }; \
	done; \
	for t in pdftotext pdfinfo; do \
	  command -v $$t >/dev/null || { echo "missing: $$t (poppler-utils)"; missing=1; }; \
	done; \
	for t in qpdf shellcheck; do \
	  command -v $$t >/dev/null || echo "optional, not found: $$t"; \
	done; \
	command -v uv >/dev/null \
	  || python3 -c 'import pypdf' 2>/dev/null \
	  || echo "optional, not found: uv (https://docs.astral.sh/uv/) — needed for the pypdf assertions"; \
	[ $$missing -eq 0 ] || { echo; echo "Install the required tools, then re-run 'make setup'."; exit 3; }; \
	echo "toolchain ok: pandoc $$(pandoc --version | head -1 | awk '{print $$2}')"

test: ## Run the full suite
	@go test ./...
	@./tests/run.sh

test-fast: ## Run only the assertions that need pandoc (no TeX, seconds)
	@./tests/run.sh --no-pdf

SHELL_FILES := tests/run.sh tests/calt-mwe/run.sh tests/no-leaks.sh .githooks/pre-commit

lint: ## shellcheck every script
	@# One shell: a bare `exit 0` in a guard only ends ITS line, so a second
	@# recipe line would run shellcheck anyway and fail with 127.
	@# LC_ALL is load-bearing: shellcheck writes findings through the locale
	@# encoding, and under a non-UTF-8 locale an em-dash in a message aborts its
	@# output mid-stream with "commitBuffer: invalid argument", after which it
	@# reports spurious parse errors in later files.
	@if command -v shellcheck >/dev/null; then \
	  LC_ALL=C.UTF-8 shellcheck $(SHELL_FILES) && echo "shellcheck clean"; \
	else \
	  echo "shellcheck not installed — skipped locally, enforced in CI"; \
	fi
	@go vet ./... && echo "go vet clean"
	@# gofmt was enforced nowhere, and cmd/schriftsatz/main.go had been sitting
	@# unformatted on main as a result. go vet does not check formatting.
	@unformatted=$$(gofmt -l cmd internal); \
	 if [ -n "$$unformatted" ]; then \
	   echo "gofmt would change:"; echo "$$unformatted" | sed 's/^/  /'; exit 1; \
	 else echo "gofmt clean"; fi
	@if command -v luacheck >/dev/null; then \
	  luacheck filters/ && echo "luacheck clean"; \
	else \
	  echo "luacheck not installed — skipped locally, enforced in CI"; \
	fi
	@# A YAML parser accepts workflows that GitHub rejects: a bare SHA with no
	@# owner/repo, or double quotes inside a ${{ }} expression, both parse as
	@# valid YAML and then fail at run time with no jobs and no error surfaced.
	@if command -v actionlint >/dev/null; then \
	  actionlint && echo "actionlint clean"; \
	elif command -v docker >/dev/null; then \
	  docker run --rm -v "$$PWD":/repo -w /repo rhysd/actionlint:latest && echo "actionlint clean (container)"; \
	else \
	  echo "actionlint not available — skipped locally, enforced in CI"; \
	fi

fmt: ## Report formatting problems (trailing whitespace, tabs, missing final newline)
	@# POSIX bracket expressions, not grep -P. -P is a GNU extension that stock
	@# macOS /usr/bin/grep rejects outright, and because the check was written as
	@# `grep -qP ... && bad=1` the error made it report "formatting clean" — it
	@# failed OPEN, which is the worst way for a check to break.
	@bad=0; \
	while IFS= read -r f; do \
	  if grep -qE '[[:blank:]]+$$' "$$f"; then echo "trailing whitespace: $$f"; bad=1; fi; \
	  if [ -n "$$(tail -c1 "$$f")" ]; then echo "no final newline: $$f"; bad=1; fi; \
	done < <(git ls-files '*.sh' '*.lua' '*.tex' '*.md' 'bin/*'); \
	if [ $$bad -eq 0 ]; then echo "formatting clean"; else exit 1; fi

check: lint test ## What CI runs
	@./tests/no-leaks.sh

# Examples are built with the FULL style set. formal-document.md redefines
# \docimprint, which only exists once formal.tex is included — building the
# examples with the default set would fail on it, and that failure is the point
# of having this target at all.
# Examples are built with the FULL style set. formal-document.md redefines
# \docimprint, which only exists once formal.tex is included.
STYLES := --style styles/text-layer.tex --style styles/linebreaking.tex --style styles/formal.tex

bin: ## Compile the binary only (no TeX needed)
	@# Separate from `build` because compiling needs Go and nothing else, while
	@# building the examples needs a TeX distribution. The fast CI job has the
	@# former and deliberately not the latter.
	@cp filters/*.lua internal/assets/filters/
	@cp styles/*.tex  internal/assets/styles/
	@mkdir -p build
	@go build -trimpath -ldflags '$(LDFLAGS)' -o $(BIN) ./cmd/schriftsatz
	@echo "  $(BIN) ($(VERSION))"

build: bin ## Compile the binary and build every example (needs TeX)
	@for f in examples/*.md; do \
	  $(BIN) "$$f" $(STYLES) -o "build/$$(basename "$${f%.md}").pdf" >/dev/null || exit 1; \
	  echo "  build/$$(basename "$${f%.md}").pdf"; \
	done

run: ## Build one document: make run DOC=path/to/file.md
	@[ -n "$(DOC)" ] || { echo "usage: make run DOC=file.md"; exit 2; }
	@$(MAKE) -s build >/dev/null
	@$(BIN) "$(DOC)"

version: ## Print the version this tree represents
	@echo $(VERSION)

next: ## Print the version the next release would carry
	@# What git-cliff would bump to, given the commits since the last tag.
	@# This is the number a merge to main will publish once #30 lands.
	@if command -v git-cliff >/dev/null; then \
	  git-cliff --bumped-version 2>/dev/null; \
	else \
	  docker run --rm -v "$$PWD":/repo -w /repo orhunp/git-cliff:latest \
	    --bumped-version 2>/dev/null; \
	fi

release-dryrun: ## Rehearse the whole release against a mock GitHub (needs docker)
	@# Everything a real release does — build, archive, checksum, create the
	@# release, upload assets, push the cask — against a socket instead of
	@# github.com. Nothing leaves the machine and no tag is created here.
	@./tests/release-dryrun.sh

changelog: ## Regenerate CHANGELOG.md from the commit history
	@# Generated, never hand-edited: each entry's prose is the pull request
	@# description, which squash-merging puts into the commit body.
	@# --bump, not --tag: git-cliff computes the next version from the
	@# Conventional Commits since the last tag. Passing --tag "v$(VERSION)"
	@# would now pass a DEV version (0.1.1-dev.5+abc1234) and write a heading
	@# for a release that will never exist.
	@if command -v git-cliff >/dev/null; then \
	  git-cliff --bump -o CHANGELOG.md; \
	else \
	  docker run --rm -v "$$PWD":/repo -w /repo orhunp/git-cliff:latest \
	    --bump -o CHANGELOG.md; \
	fi
	@echo "  CHANGELOG.md regenerated for $$(make -s next)"

release: ## How to cut a release
	@echo "Releases are tag-driven and the tag push is a human action:"
	@echo
	@echo "  1. make changelog VERSION=X.Y.Z   # regenerate, review, open a PR, merge"
	@echo "  2. make release-dryrun            # rehearse it against a mock GitHub"
	@echo "  3. git tag -a vX.Y.Z -m vX.Y.Z"
	@echo "  4. git push origin vX.Y.Z"
	@echo
	@echo "Step 2 is the one that is easy to skip and should not be. A tag is"
	@echo "immutable, so anything wrong with what it publishes is permanent."
	@echo
	@echo "The workflow then validates semver, ancestry and the changelog entry,"
	@echo "builds every platform, and pushes the Homebrew cask."

clean: ## Remove generated output
	@rm -rf build
	@go clean -cache -testcache 2>/dev/null || true
	@echo "clean"
