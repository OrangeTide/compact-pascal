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
.PHONY: check-wasm-features check-rust release preflight check-determinism check-selfhost-gen2 check-runtimes check-doc-examples check-windows check-playground

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
	@echo "  preflight            Every check runnable on this machine; run before pushing"
	@echo "  release              Build and verify build/release/compact-pascal-VERSION.zip"
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

# ── Checks CI does not run ───────────────────────────────────────

# The same source compiled twice must give the same bytes. Cheap, and the
# only thing that catches a compiler that has become sensitive to something
# outside its input — an uninitialised buffer, a stale global between runs.
check-determinism: $(CPAS_BIN)
	@$(CPAS_BIN) < $(CPAS_SRC) > $(BUILD_DIR)/det-a.wasm
	@$(CPAS_BIN) < $(CPAS_SRC) > $(BUILD_DIR)/det-b.wasm
	@cmp $(BUILD_DIR)/det-a.wasm $(BUILD_DIR)/det-b.wasm \
	  && echo "check-determinism: two runs, identical output" \
	  || { echo "::error::the compiler is not deterministic" >&2; exit 1; }

# check-fixpoint compares the fpc-built compiler against the snapshot. This
# goes one generation further: the snapshot compiles the source, and what it
# produces compiles the source to the same bytes again. A compiler can agree
# with its parent and still be wrong about itself.
check-selfhost-gen2: $(SNAPSHOT)
	@mkdir -p $(BUILD_DIR)
	@$(WASMRUN) $(SNAPSHOT) < $(CPAS_SRC) > $(BUILD_DIR)/gen2.wasm
	@$(WASMRUN) $(BUILD_DIR)/gen2.wasm < $(CPAS_SRC) > $(BUILD_DIR)/gen3.wasm
	@cmp $(BUILD_DIR)/gen2.wasm $(BUILD_DIR)/gen3.wasm \
	  && echo "check-selfhost-gen2: second generation is a fixpoint" \
	  || { echo "::error::generation 2 and 3 differ" >&2; exit 1; }

# The suite under a second runtime. Two interpreters disagreeing is how a
# dependence on one runtime's tolerance shows up; wasmtime and wasmer differ
# in trap reporting, which the runner already accounts for.
# wasmer 7.1 will not create a new file inside a --dir preopen: path_open with
# O_CREAT answers ENOTDIR. Opening a file that already exists works, and so
# does everything else, so this is a limitation of that runtime rather than a
# portability defect here — the same oflags and rights succeed under wasmtime,
# and rewriting an existing file succeeds under wasmer.
#
# The two tests that create files are therefore expected to fail. Pinned as a
# set rather than skipped, so this notices if wasmer starts working or if a
# different test breaks.
WASMER_EXPECTED_FAILURES := t117_text_write_read t120_read_past_eof

check-runtimes: $(CPAS_BIN)
	@if ! command -v wasmer >/dev/null 2>&1; then \
	  echo "check-runtimes: wasmer not installed, skipped"; \
	else \
	  out=$$(bash compiler-tests/run-tests.sh wasmer 2>&1 || true); \
	  got=$$(printf '%s\n' "$$out" | sed -n 's/^FAIL \([a-z0-9_]*\).*/\1/p' | sort | tr '\n' ' '); \
	  want=$$(printf '%s\n' $(WASMER_EXPECTED_FAILURES) | sort | tr '\n' ' '); \
	  if [ "$$got" = "$$want" ]; then \
	    echo "check-runtimes: wasmer agrees with wasmtime except the known file-creation limit"; \
	  else \
	    echo "::error::wasmer failures changed" >&2; \
	    echo "  expected: $$want" >&2; \
	    echo "  got:      $$got" >&2; \
	    exit 1; \
	  fi; \
	fi

# Every self-contained example in the documentation, compiled and run.
check-doc-examples: $(CPAS_BIN)
	@bash compiler-tests/check-doc-examples.sh

# The compiler cross-compiled for Windows must produce the same bytes. Needs
# fp-units-win-rtl and wine; skipped with a note rather than failing when
# either is missing, so this stays runnable on a bare machine.
check-windows:
	@if ! fpc -Twin64 -FE$(BUILD_DIR) -o$(BUILD_DIR)/cross-probe.exe \
	     /dev/null >/dev/null 2>&1 && \
	     ! printf 'begin end.\n' > $(BUILD_DIR)/probe.pas 2>/dev/null; then \
	  echo "check-windows: cannot write probe, skipped"; \
	elif ! command -v wine >/dev/null 2>&1; then \
	  echo "check-windows: wine not installed, skipped"; \
	else \
	  mkdir -p $(BUILD_DIR)/win64; \
	  printf 'begin end.\n' > $(BUILD_DIR)/probe.pas; \
	  if fpc -Twin64 -FE$(BUILD_DIR) -o$(BUILD_DIR)/probe.exe \
	       $(BUILD_DIR)/probe.pas >/dev/null 2>&1; then \
	    fpc -Mtp -Twin64 -FE$(BUILD_DIR)/win64 $(CPAS_SRC) >/dev/null && \
	    WINEDEBUG=-all wine $(BUILD_DIR)/win64/cpas.exe < $(CPAS_SRC) \
	      > $(BUILD_DIR)/windows.wasm 2>/dev/null && \
	    cmp $(BUILD_DIR)/windows.wasm $(SNAPSHOT) \
	      && echo "check-windows: byte-identical to the snapshot" \
	      || { echo "::error::the Windows build disagrees with the snapshot" >&2; exit 1; }; \
	  else \
	    echo "check-windows: no win64 RTL (fp-units-win-rtl-3.2.2), skipped"; \
	  fi; \
	fi

# The docs workflow deploys the playground on every push that touches doc/,
# pages/, compiler/, or the Makefile — which is most of them. The deployed
# compiler.wasm is generated and gitignored, so what is worth checking is not
# whether the local copy is current but whether the deploy step still works
# and copies the right bytes. A broken one is only visible on the published
# site otherwise.
check-playground: $(SNAPSHOT)
	@$(MAKE) --no-print-directory deploy-playground >/dev/null
	@cmp -s $(SNAPSHOT) $(PAGES_DIR)/playground/compiler.wasm \
	  && cmp -s $(CPAS_SRC) $(PAGES_DIR)/playground/samples/cpas.pas \
	  && echo "check-playground: deploy reproduces the snapshot and sample" \
	  || { echo "::error::deploy-playground did not copy what it should" >&2; exit 1; }

# The documented WASM feature set is MVP plus bulk memory, and nothing else.
# That claim sat in the reference as a conformance requirement while being
# false — the compiler has needed memory.copy since structured assignment
# landed, and nobody checked. Each feature is disabled in turn: bulk memory
# must be required and every other must not be.
check-wasm-features: $(SNAPSHOT)
	@fail=0; \
	for f in mutable-globals saturating-float-to-int sign-extension simd \
	         multi-value reference-types; do \
	  if ! wasm-validate --disable-$$f $(SNAPSHOT) >/dev/null 2>&1; then \
	    echo "::error::the compiler now needs the $$f proposal, which the documentation says it does not" >&2; \
	    fail=1; \
	  fi; \
	done; \
	if wasm-validate --disable-bulk-memory $(SNAPSHOT) >/dev/null 2>&1; then \
	  echo "check-wasm-features: bulk memory is no longer needed; the docs can be tightened"; \
	fi; \
	[ $$fail -eq 0 ] && echo "check-wasm-features: MVP plus bulk memory, as documented"

# The Rust crate, exactly as CI checks it. Not in test-all because that target
# is the Pascal side and runs where cargo may not exist.
check-rust:
	@if ! command -v cargo >/dev/null 2>&1; then \
	  echo "check-rust: cargo not installed, skipped"; \
	else \
	  cargo build --quiet && \
	  cargo test --quiet && \
	  cargo clippy --all-targets --quiet -- -D warnings && \
	  for e in hello calculator host-callback; do \
	    cargo run --quiet --example $$e >/dev/null || exit 1; \
	  done && \
	  echo "check-rust: crate builds, tests pass, clippy clean, examples run"; \
	fi

# Build the release artifact and prove it works: validate the module, compile
# a program with it, and run what it produced.
release: $(SNAPSHOT)
	@bash compiler-tests/build-release.sh

# Everything that can be checked on this machine. Run before pushing: CI is
# a second opinion, not the first one.
preflight: test-all check-determinism check-selfhost-gen2 check-doc-examples \
           check-windows check-playground check-runtimes check-wasm-features \
           check-rust release
	@echo ""
	@echo "preflight: every local check passed"
	@echo "  not covered here: macOS. CI is the only place that runs it."

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
