all: create check

create:
	sudo -u postgres ./mg_to_static.pl

check:
	echo 'FIXME - check $MG_ROOT against all HREFS'
	
.PHONY: all create check

	