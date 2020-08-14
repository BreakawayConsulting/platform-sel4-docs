NAME=sel4-platform
Md2Pdf	   = pandoc

.PHONY: all

all:	$(NAME).pdf

%.pdf:	%.md
	$(Md2Pdf) $< -o $@

clean:

realclean:	clean
	rm $(NAME).pdf
