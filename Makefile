all: create check

create:
	sudo -u postgres ./mg_to_static.pl

MG_ROOT=$(shell sed -ne "s/^.*MG_ROOT *= *'\(.*\)';.*/\1/p" mg_to_static.pl)
NEW_ROOT=$(shell sed -ne "s/^.*NEW_ROOT *= *'\(.*\)';.*/\1/p" mg_to_static.pl)
C_ORG=$(shell find $(MG_ROOT) -type f -iname "*.thumbnail.*" | wc -l)
C_MY=$(shell fgrep -h 'IMG SRC=' mg_html/u/*/m/*/index.html | sed -e 's/^.*IMG SRC="\(.*\)">/\1/' | sort -u | wc -l)

check:
	[ "$(C_ORG)" = "$(C_MY)" ]

.PHONY: all create check
	