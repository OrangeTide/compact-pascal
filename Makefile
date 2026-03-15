.PHONY: pdf clean

PANDOC := pandoc
TYPST := typst

PDF_DIR := build
WP_PDF := $(PDF_DIR)/compact-pascal-wp.pdf
REF_PDF := $(PDF_DIR)/compact-pascal-ref.pdf

PANDOC_FLAGS := --pdf-engine=$(TYPST) \
	--table-of-contents \
	--number-sections \
	-V mainfont="TeX Gyre Pagella" \
	-V sansfont="TeX Gyre Heros" \
	-V monofont="TeX Gyre Cursor" \
	-V fontsize=11pt

pdf: $(WP_PDF) $(REF_PDF)

$(PDF_DIR):
	mkdir -p $(PDF_DIR)

$(WP_PDF): doc/compact-pascal-wp.md | $(PDF_DIR)
	$(PANDOC) $< -o $@ $(PANDOC_FLAGS)

$(REF_PDF): doc/compact-pascal-ref.md | $(PDF_DIR)
	$(PANDOC) $< -o $@ $(PANDOC_FLAGS)

clean:
	rm -rf $(PDF_DIR)
