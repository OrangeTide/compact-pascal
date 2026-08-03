.POSIX:

# ── Toolchain ────────────────────────────────────────────────────

PANDOC   := pandoc
TYPST    := typst

# ── Directories ──────────────────────────────────────────────────

BUILD_DIR := build
PAGES_DIR := pages

# ── PDF / HTML sources ───────────────────────────────────────────

WP_PDF       := $(BUILD_DIR)/compact-pascal-wp.pdf
REF_PDF      := $(BUILD_DIR)/compact-pascal-ref.pdf
TUTORIAL_PDF := $(BUILD_DIR)/compact-pascal-tutorial.pdf
TN_SRC       := $(wildcard doc/compact-pascal-tn*.md)
TN_PDF       := $(patsubst doc/%.md,$(BUILD_DIR)/%.pdf,$(TN_SRC))
TN_HTML      := $(patsubst doc/%.md,$(PAGES_DIR)/%.html,$(TN_SRC))

WP_HTML       := $(PAGES_DIR)/compact-pascal-wp.html
REF_HTML      := $(PAGES_DIR)/compact-pascal-ref.html
TUTORIAL_HTML := $(PAGES_DIR)/compact-pascal-tutorial.html

TEMPLATE := doc/article-template.html

PANDOC_FLAGS := --pdf-engine=$(TYPST) \
	--table-of-contents \
	--number-sections \
	--resource-path=doc \
	--pdf-engine-opt=--root --pdf-engine-opt=/ \
	-V mainfont="TeX Gyre Pagella" \
	-V sansfont="TeX Gyre Heros" \
	-V monofont="TeX Gyre Cursor" \
	-V fontsize=11pt

BOOK_FLAGS := $(PANDOC_FLAGS) \
	--top-level-division=chapter \
	-V papersize=a5 \
	-V margin-top=2cm \
	-V margin-bottom=2cm \
	-V margin-left=2cm \
	-V margin-right=2cm

HTML_FLAGS := --template=$(TEMPLATE) \
	--table-of-contents \
	--number-sections \
	--standalone \
	--resource-path=doc \
	--shift-heading-level-by=0

# ── Top-level targets ────────────────────────────────────────────

.PHONY: help all pdf html clean
.PHONY: bootstrap test test-checks check-private check-fixpoint test-all deploy-playground bump-version

help:
	@echo "Compact Pascal build targets:"
	@echo ""
	@echo "  all          Bootstrap the compiler and run everything CI runs"
	@echo "  pdf          Generate PDF documentation"
	@echo "  html         Generate HTML documentation"
	@echo "  clean        Remove build artifacts"
	@echo ""
	@echo "  bootstrap            Rebuild snapshot/compiler.wasm from source (requires fpc)"
	@echo "  test                 Run compiler test suite (requires fpc + WASM runtime)"
	@echo "  deploy-playground    Copy compiler.wasm into pages/playground/"
	@echo "  check-private        Fail if tracked files leak local paths or private info"
	@echo "  check-fixpoint       Verify snapshot is current and self-hosting holds"
	@echo "  test-checks          Run the test suite with checks on, then with checks off"
	@echo "  test-all             Everything CI runs (check-private test test-checks check-fixpoint)"
	@echo "  bump-version VERSION=YY.MM.PATCH"
	@echo "                       Update version in compiler and docs, commit"

all: bootstrap test-all

# ── Output directories ───────────────────────────────────────────

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# ── PDF documentation ────────────────────────────────────────────

pdf: $(WP_PDF) $(REF_PDF) $(TUTORIAL_PDF) $(TN_PDF)

$(WP_PDF): doc/compact-pascal-wp.md | $(BUILD_DIR)
	$(PANDOC) $< -o $@ $(PANDOC_FLAGS)

$(REF_PDF): doc/compact-pascal-ref.md | $(BUILD_DIR)
	$(PANDOC) $< -o $@ $(PANDOC_FLAGS)

$(TUTORIAL_PDF): doc/compact-pascal-tutorial.md | $(BUILD_DIR)
	$(PANDOC) $< -o $@ $(BOOK_FLAGS)

$(BUILD_DIR)/compact-pascal-tn%.pdf: doc/compact-pascal-tn%.md | $(BUILD_DIR)
	$(PANDOC) $< -o $@ $(PANDOC_FLAGS)

# ── HTML documentation ───────────────────────────────────────────

html: $(WP_HTML) $(REF_HTML) $(TUTORIAL_HTML) $(TN_HTML)

$(WP_HTML): doc/compact-pascal-wp.md $(TEMPLATE) | $(PAGES_DIR)
	$(PANDOC) $< -o $@ $(HTML_FLAGS) \
		-V category="White Paper" \
		-V pdf-file="compact-pascal-wp.pdf" \
		-V md-file="compact-pascal-wp.md"

$(REF_HTML): doc/compact-pascal-ref.md $(TEMPLATE) | $(PAGES_DIR)
	$(PANDOC) $< -o $@ $(HTML_FLAGS) \
		-V category="Language Reference" \
		-V pdf-file="compact-pascal-ref.pdf" \
		-V md-file="compact-pascal-ref.md"

$(TUTORIAL_HTML): doc/compact-pascal-tutorial.md $(TEMPLATE) | $(PAGES_DIR)
	$(PANDOC) $< -o $@ $(HTML_FLAGS) \
		--top-level-division=chapter \
		-V category="Tutorial" \
		-V pdf-file="compact-pascal-tutorial.pdf" \
		-V md-file="compact-pascal-tutorial.md"

$(PAGES_DIR)/compact-pascal-tn%.html: doc/compact-pascal-tn%.md $(TEMPLATE) | $(PAGES_DIR)
	$(PANDOC) $< -o $@ $(HTML_FLAGS) \
		-V category="Technical Note" \
		-V pdf-file="$(notdir $(patsubst %.html,%.pdf,$@))" \
		-V md-file="$(notdir $<)"

# ── Bootstrap ────────────────────────────────────────────────────
#
# Rebuilds the self-hosted compiler WASM snapshot from Pascal source.
# Requires: fpc (Free Pascal, TP mode) and a WASM runtime (wasmtime or wasmer).
# Not part of 'make all' — end users just embed the checked-in snapshot.

CPAS_SRC  := compiler/cpas.pas
CPAS_BIN  := compiler/cpas
SNAPSHOT  := snapshot/compiler.wasm

# WASM runtime used to execute the snapshot. Override to use wasmer:
#   make check-fixpoint WASMRUN="wasmer run"
WASMRUN   := wasmtime run

bootstrap: $(SNAPSHOT)

$(CPAS_BIN): $(CPAS_SRC)
	fpc -Mtp -o$@ $<

$(SNAPSHOT): $(CPAS_BIN) $(CPAS_SRC)
	$(CPAS_BIN) < $(CPAS_SRC) > $@
	@wasm-validate $@ && echo "snapshot/compiler.wasm: valid"

# ── Test ─────────────────────────────────────────────────────────

test: $(CPAS_BIN)
	bash compiler-tests/run-tests.sh

# Run the suite under both check configurations. The generated code differs
# between them, so passing one says nothing about the other: checks-on can
# hide a codegen bug behind a trap, and checks-off can hide a bug in the
# checks themselves. Tests that must pin a setting do so with a directive.
test-checks: $(CPAS_BIN)
	@echo "── checks on ──"
	CPASFLAGS='-S+ -R+' bash compiler-tests/run-tests.sh
	@echo "── checks off ──"
	CPASFLAGS='-S- -R-' bash compiler-tests/run-tests.sh

# Fail if a tracked file leaks private info (local paths, personal domains).
check-private:
	@bash compiler-tests/check-private-info.sh

# Verify the committed snapshot is current and self-hosting holds.
#
#   fixpoint  the snapshot compiling its own source reproduces itself, byte
#             for byte.  This is the project's strongest correctness signal.
#   currency  the committed snapshot matches what the current source builds,
#             so nobody can land a compiler change and forget to bootstrap.
#
# Uses a temp dir so a failure leaves no half-built artifact behind.
check-fixpoint: $(CPAS_BIN)
	@tmp=$$(mktemp -d); 	trap 'rm -rf "$$tmp"' EXIT; 	$(CPAS_BIN) < $(CPAS_SRC) > "$$tmp/gen1.wasm"; 	if ! cmp -s "$$tmp/gen1.wasm" $(SNAPSHOT); then 	    echo "check-fixpoint: committed snapshot is stale; run 'make bootstrap'" >&2; 	    exit 1; 	fi; 	$(WASMRUN) $(SNAPSHOT) < $(CPAS_SRC) > "$$tmp/gen2.wasm"; 	if ! cmp -s "$$tmp/gen1.wasm" "$$tmp/gen2.wasm"; then 	    echo "check-fixpoint: fixpoint broken; self-compiled output differs" >&2; 	    exit 1; 	fi; 	echo "check-fixpoint: snapshot current, fixpoint holds"

# Everything CI runs, reproducible locally.
test-all: check-private test test-checks check-fixpoint
	@echo "test-all: all checks passed"

# ── Deploy ───────────────────────────────────────────────────────

deploy-playground:
	cp $(SNAPSHOT) pages/playground/compiler.wasm
	cp $(CPAS_SRC) pages/playground/samples/cpas.pas
	jq '. | if any(.file == "cpas.pas") then . else . + [{"name":"Compiler Source","file":"cpas.pas","description":"The Compact Pascal compiler itself"}] end' \
		pages/playground/files.json > pages/playground/files.json.tmp
	mv pages/playground/files.json.tmp pages/playground/files.json
	@echo "pages/playground/: updated"

# ── Version ──────────────────────────────────────────────────────
#
# Usage:  make bump-version VERSION=26.04.1
# Updates compiler constants and doc CalVer, stages files, and
# opens git commit with a template message.

bump-version:
	@if [ -z "$(VERSION)" ]; then echo "Usage: make bump-version VERSION=YY.MM.PATCH"; exit 1; fi
	@YY=$$(echo "$(VERSION)" | cut -d. -f1) && \
	 MM=$$(echo "$(VERSION)" | cut -d. -f2) && \
	 PATCH=$$(echo "$(VERSION)" | cut -d. -f3) && \
	 if [ -z "$$YY" ] || [ -z "$$MM" ] || [ -z "$$PATCH" ]; then \
	   echo "error: VERSION must be YY.MM.PATCH (e.g., 26.04.0)"; exit 1; \
	 fi && \
	 sed -i \
	   -e "s/Version = '.*'/Version = '$(VERSION)'/" \
	   -e "s/VersionYear = .*/VersionYear = $$YY;/" \
	   -e "s/VersionMonth = .*/VersionMonth = $$MM;/" \
	   -e "s/VersionPatch = .*/VersionPatch = $$PATCH;/" \
	   $(CPAS_SRC) && \
	 sed -i \
	   -e "s/\*\*Version [0-9][0-9]\.[0-9][0-9]*\.[0-9][0-9]*\*\*/**Version $(VERSION)**/" \
	   doc/compact-pascal-ref.md \
	   doc/compact-pascal-wp.md \
	   doc/compact-pascal-tutorial.md && \
	 git add $(CPAS_SRC) doc/compact-pascal-ref.md \
	   doc/compact-pascal-wp.md doc/compact-pascal-tutorial.md && \
	 git commit -e -m "Bump version to $(VERSION)"

# ── Cleanup ──────────────────────────────────────────────────────

clean:
	rm -f $(WP_PDF) $(REF_PDF) $(TUTORIAL_PDF) $(TN_PDF)
	$(if $(wildcard $(BUILD_DIR)),rmdir $(BUILD_DIR),: skipped removing $(BUILD_DIR) directory)
	rm -f $(CPAS_BIN) compiler/cpas.o
	@echo "clean: the Rust crate is cleaned with 'cargo clean'"
