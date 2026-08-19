# schriftsatz — one frontend. CI runs these same targets.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

VERSION := $(shell sed -n 's/^VERSION="\(.*\)"/\1/p' bin/schriftsatz)

.PHONY: help setup check test test-fast lint fmt build run clean release version

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
	@./tests/run.sh

test-fast: ## Run only the assertions that need pandoc (no TeX, seconds)
	@./tests/run.sh --no-pdf

SHELL_FILES := bin/schriftsatz scripts/release.sh tests/run.sh tests/calt-mwe/run.sh tests/no-leaks.sh .githooks/pre-commit

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
STYLES := --style styles/text-layer.tex --style styles/linebreaking.tex --style styles/formal.tex

build: ## Build every example into build/ (ignored) with the full style set
	@mkdir -p build
	@for f in examples/*.md; do \
	  ./bin/schriftsatz "$$f" $(STYLES) -o "build/$$(basename "$${f%.md}").pdf" >/dev/null || exit 1; \
	  echo "  build/$$(basename "$${f%.md}").pdf"; \
	done

run: ## Build one document: make run DOC=path/to/file.md
	@[ -n "$(DOC)" ] || { echo "usage: make run DOC=file.md"; exit 2; }
	@./bin/schriftsatz "$(DOC)"

version: ## Print the version
	@echo $(VERSION)

release: ## Tag a release (refuses on a dirty tree or off main)
	@./scripts/release.sh

clean: ## Remove generated output
	@rm -rf build
	@echo "clean"
