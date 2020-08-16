### Configure options
NAME=sel4-platform
Md2Pdf	   = pandoc
Md2Tex     = pandoc --biblatex 
LaTeX      = pdflatex -interaction=nonstopmode

### Macros
GEN=generated
ROOT=root

.PHONY: all
.SECONDARY: $(NAME).tex

all:	$(NAME).pdf #nice.pdf

%.tex:	%.md Makefile defaults.yaml
	$(Md2Tex) $< -o - -d defaults.yaml -t latex -N > $@

%.pdf:	%.tex
	$(LaTeX) $<
	$(LaTeX) $<

clean:
	rm -f $(GEN).* *.log *.aux *.out *.bcf *.xml *.tex

realclean:	clean
	rm -f *.pdf
