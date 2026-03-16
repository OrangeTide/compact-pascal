.PHONY: pdf clean

PANDOC := pandoc
TYPST := typst

PDF_DIR := build
WP_PDF := $(PDF_DIR)/compact-pascal-wp.pdf
REF_PDF := $(PDF_DIR)/compact-pascal-ref.pdf
TUTORIAL_PDF := $(PDF_DIR)/compact-pascal-tutorial.pdf

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

pdf: $(WP_PDF) $(REF_PDF) $(TUTORIAL_PDF)

$(PDF_DIR):
	mkdir -p $(PDF_DIR)

$(WP_PDF): doc/compact-pascal-wp.md | $(PDF_DIR)
	$(PANDOC) $< -o $@ $(PANDOC_FLAGS)

$(REF_PDF): doc/compact-pascal-ref.md | $(PDF_DIR)
	$(PANDOC) $< -o $@ $(PANDOC_FLAGS)

$(TUTORIAL_PDF): doc/compact-pascal-tutorial.md | $(PDF_DIR)
	$(PANDOC) $< -o $@ $(BOOK_FLAGS)

clean:
	rm -rf $(PDF_DIR)
