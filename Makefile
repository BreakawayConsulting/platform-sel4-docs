# Copyright seL4 Project a Series of LF Projects, LLC.
# SPDX-License-Identifier: CC-BY-SA-4.0

#######################
### Set this to the basename(s) of your .md document(s)
NAMES=sel4-platform sel4-core

### Configure options
Md2Pdf	   = pandoc
Md2Tex     = pandoc -f markdown+raw_tex+implicit_figures+link_attributes #--biblatex 
LaTeX      = pdflatex -interaction=nonstopmode

### Macros 
Rerun = '(There were undefined (references|citations)|Rerun to get (cross-references|the bars) right)'
Rerun_Bib = 'No file.*\.bbl|Citation.*undefined'
Undefined = '((Reference|Citation).*undefined)|(Label.*multiply defined)'
Error = '^! '
BibWarn = '^Warning--'
LaTeXWarn = ' [Ww]arning: '
Pdf = $(addsuffix .pdf, $(NAMES))
Tex = $(addsuffix .tex, $(NAMES))

.PHONY: all
.SECONDARY: $(Tex)

all:	$(Pdf)

%.tex:	%.md Makefile defaults.yaml sel4.sty
	$(Md2Tex) $< -o - -d defaults.yaml -t latex -N | \
	sed -e '/^ *hidelinks,/d' > $@

%.pdf:	%.tex
#	Assume for now that there's no bibtex run needed
	@echo "====> LaTeX first pass: $(<)"
	$(LaTeX) $< >.log || if egrep -q $(Error) $*.log ; then cat .log; rm $@; false ; fi
	@if egrep -q $(Rerun) $*.log ; then echo "====> LaTeX rerun" && $(LaTeX) >.log $<; fi
	@echo "====> Undefined references and citations in $(<):"
	@egrep -i $(Undefined) $*.log || echo "None."
	@echo "====> Warnings:"
	@bibw=`if test -e $*.blg; then grep -c $(BibWarn) $*.blg; else echo 0; fi`; \
	texw=`grep -c $(LaTeXWarn) $*.log`; \
	if [ "$$bibw" -gt 0 ]; then echo " $$bibw BibTeX\c"; fi; \
	if [ "$$texw" -gt 0 ]; then echo " $$texw LaTeX\c"; fi; \
	if [ "$$bibw$$texw" = 00 ]; then echo "None."; \
	else echo ". 'make warn' will show them."; fi

warn:
	@if test -e $*.blg; then \
	echo "====> BibTeX warnings from" *.blg; \
	grep $(BibWarn) *.blg || echo "None."; \
	fi
	@echo "====> LaTeX warnings from" *.log
	@grep $(LaTeXWarn) *.log || echo "None."

clean:
	rm -f *.log *.aux *.out *.bcf *.xml *.tex

realclean:	clean
	rm -f *.pdf
