.POSIX:

# ── Toolchain ────────────────────────────────────────────────────

CC       := cc
AR       := ar
PANDOC   := pandoc
TYPST    := typst

CFLAGS   := -std=c11 -Wall -Wextra -Wpedantic
LDFLAGS  :=

# Relaxed warnings for vendored wasm3 sources
WASM3_CFLAGS := -std=c11 -Wall \
	-Wno-unused-parameter -Wno-unused-variable \
	-Wno-missing-field-initializers -Wno-sign-compare

# ── Directories ──────────────────────────────────────────────────

BUILD_DIR := build
PAGES_DIR := pages

# ── C sources ────────────────────────────────────────────────────

CP_SRC   := src/c/compact_pascal.c
CP_OBJ   := $(BUILD_DIR)/compact_pascal.o
CP_LIB   := $(BUILD_DIR)/libcompact_pascal.a

WASM3_SRC := $(wildcard vendor/wasm3/*.c)
WASM3_OBJ := $(patsubst vendor/wasm3/%.c,$(BUILD_DIR)/wasm3/%.o,$(WASM3_SRC))
WASM3_LIB := $(BUILD_DIR)/libwasm3.a

HELLO_SRC := examples/c/hello/main.c
HELLO_BIN := examples/c/hello/hello

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

.PHONY: help all all-c all-zig all-rust pdf html clean clean-c clean-zig clean-rust
.PHONY: bootstrap test deploy-playground

help:
	@echo "Compact Pascal build targets:"
	@echo ""
	@echo "  all          Build everything (all-c all-zig all-rust)"
	@echo "  all-c        Build C libraries, tools, tests, and examples"
	@echo "  all-zig      Build Zig library (not yet implemented)"
	@echo "  all-rust     Build Rust crate (not yet implemented)"
	@echo "  pdf          Generate PDF documentation"
	@echo "  html         Generate HTML documentation"
	@echo "  clean        Remove build artifacts"
	@echo ""
	@echo "  bootstrap        Rebuild snapshot/compiler.wasm from source (requires fpc)"
	@echo "  test             Run compiler test suite (requires fpc + WASM runtime)"
	@echo "  deploy-playground  Copy compiler.wasm into pages/playground/"

all: all-c all-zig all-rust

all-c: lib-c lib-wasm3 example-c-hello

all-zig:
	@echo "all-zig: not yet implemented"

all-rust:
	@echo "all-rust: not yet implemented"

# ── C library ────────────────────────────────────────────────────

.PHONY: lib-c lib-wasm3 example-c-hello

lib-c: $(CP_LIB)

$(CP_OBJ): $(CP_SRC) src/c/compact_pascal.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(CP_LIB): $(CP_OBJ)
	$(AR) rcs $@ $^

# ── Vendored wasm3 ───────────────────────────────────────────────

lib-wasm3: $(WASM3_LIB)

$(BUILD_DIR)/wasm3/%.o: vendor/wasm3/%.c | $(BUILD_DIR)/wasm3
	$(CC) $(WASM3_CFLAGS) -c -o $@ $<

$(WASM3_LIB): $(WASM3_OBJ)
	$(AR) rcs $@ $^

# ── Examples ─────────────────────────────────────────────────────

example-c-hello: $(HELLO_BIN)

$(HELLO_BIN): $(HELLO_SRC) $(CP_LIB) $(WASM3_LIB) src/c/compact_pascal.h
	$(CC) $(CFLAGS) -Wno-pointer-arith -Wno-unused-parameter \
		-Isrc/c -Ivendor/wasm3 -o $@ $< \
		-L$(BUILD_DIR) -lcompact_pascal -lwasm3 -lm

# ── Output directories ───────────────────────────────────────────

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/wasm3:
	mkdir -p $(BUILD_DIR)/wasm3

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

bootstrap: $(SNAPSHOT)

$(CPAS_BIN): $(CPAS_SRC)
	fpc -Mtp -o$@ $<

$(SNAPSHOT): $(CPAS_BIN) $(CPAS_SRC)
	$(CPAS_BIN) < $(CPAS_SRC) > $@
	@wasm-validate $@ && echo "snapshot/compiler.wasm: valid"

# ── Test ─────────────────────────────────────────────────────────

test: $(CPAS_BIN)
	bash compiler-tests/run-tests.sh

# ── Deploy ───────────────────────────────────────────────────────

deploy-playground: $(SNAPSHOT)
	cp $(SNAPSHOT) pages/playground/compiler.wasm
	@echo "pages/playground/compiler.wasm: updated"

# ── Cleanup ──────────────────────────────────────────────────────

clean: clean-c clean-zig clean-rust

clean-c:
	rm -f $(CP_OBJ) $(CP_LIB)
	rm -f $(WASM3_OBJ) $(WASM3_LIB)
	-rmdir $(BUILD_DIR)/wasm3
	rm -f $(WP_PDF) $(REF_PDF) $(TUTORIAL_PDF) $(TN_PDF)
	$(if $(wildcard $(BUILD_DIR)),rmdir $(BUILD_DIR),: skipped removing $(BUILD_DIR) directory)
	rm -f $(HELLO_BIN)
	rm -f $(CPAS_BIN) compiler/cpas.o

clean-zig:
	@echo "clean-zig: not yet implemented"

clean-rust:
	@echo "clean-rust: not yet implemented"
