.PHONY: pdf html clean

PANDOC := pandoc
TYPST := typst

PDF_DIR := build
PAGES_DIR := pages

WP_PDF := $(PDF_DIR)/compact-pascal-wp.pdf
REF_PDF := $(PDF_DIR)/compact-pascal-ref.pdf
TUTORIAL_PDF := $(PDF_DIR)/compact-pascal-tutorial.pdf
TN_SRC := $(wildcard doc/compact-pascal-tn*.md)
TN_PDF := $(patsubst doc/%.md,$(PDF_DIR)/%.pdf,$(TN_SRC))
TN_HTML := $(patsubst doc/%.md,$(PAGES_DIR)/%.html,$(TN_SRC))

WP_HTML := $(PAGES_DIR)/compact-pascal-wp.html
REF_HTML := $(PAGES_DIR)/compact-pascal-ref.html
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

pdf: $(WP_PDF) $(REF_PDF) $(TUTORIAL_PDF) $(TN_PDF)

html: $(WP_HTML) $(REF_HTML) $(TUTORIAL_HTML) $(TN_HTML)

$(PDF_DIR):
	mkdir -p $(PDF_DIR)

$(WP_PDF): doc/compact-pascal-wp.md | $(PDF_DIR)
	$(PANDOC) $< -o $@ $(PANDOC_FLAGS)

$(REF_PDF): doc/compact-pascal-ref.md | $(PDF_DIR)
	$(PANDOC) $< -o $@ $(PANDOC_FLAGS)

$(TUTORIAL_PDF): doc/compact-pascal-tutorial.md | $(PDF_DIR)
	$(PANDOC) $< -o $@ $(BOOK_FLAGS)

$(PDF_DIR)/compact-pascal-tn%.pdf: doc/compact-pascal-tn%.md | $(PDF_DIR)
	$(PANDOC) $< -o $@ $(PANDOC_FLAGS)

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

clean:
	rm -rf $(PDF_DIR)
