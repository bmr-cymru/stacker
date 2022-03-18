#  stacker - manage device-mapper stacks for testing
#
#  Bryn M. Reeves <bmr@redhat.com>
#
#  Copyright (C) Red Hat, Inc. 2021
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

PKGNAME := stacker
VERSION := $(shell awk '/Version:/ { print $$2 }' $(PKGNAME).spec)
RELEASE := $(subst %{?dist},,$(shell awk '/Release:/ { print $$2 }' $(PKGNAME).spec))
TAG=$(PKGNAME)-$(VERSION)-$(RELEASE)

prefix ?= /usr
sysconfdir ?= /etc
statedir ?= /var
libdir ?= ${prefix}/lib
datadir ?= ${prefix}/share
pkglibdir ?= ${libdir}/stacker
pkgstatedir ?= ${statedir}/lib/stacker
bindir ?= ${prefix}/bin
mandir ?= ${datadir}/man

man8pages = man/stkr.8
manpages = $(man8pages)

layer_scripts = _layer_init.sh \
		_part_disk_init.sh \
		linear \
		loop \
		nvme \
		sd \
		thin \
		thin-pool \
		vd

.PHONY: all clean check tag changelog version release

all: $(manpages)

install: all
	mkdir -p $(DESTDIR)$(pkglibdir)
	mkdir -p $(DESTDIR)$(pkglibdir)/layers
	mkdir -p $(DESTDIR)$(bindir)
	mkdir -p $(DESTDIR)$(sysconfdir)/stacker
	mkdir -p $(DESTDIR)$(pkgstatedir)/stacks
	mkdir -p $(DESTDIR)$(mandir)/man8

	install -m755 stkr $(DESTDIR)$(bindir)
	install -m755 stacker-functions.sh $(DESTDIR)$(pkglibdir)
	install -m755 stacklog.sh $(DESTDIR)$(pkglibdir)
	install -m755 stacklib.sh $(DESTDIR)$(pkglibdir)
	install -m755 etc/stkr.conf $(DESTDIR)$(sysconfdir)/stacker
	install -m644 man/stkr.8 $(DESTDIR)$(mandir)/man8

	for l in $(layer_scripts); do install -m755 layers/$$l $(DESTDIR)$(pkglibdir)/layers/; done

check:
	@ret=0; for f in stacker-functions.sh stacklib.sh stacklog.sh layers/*; do \
		if ! file $$f | grep -s ELF  >/dev/null; then \
		    bash -n $$f || { echo $$f ; exit 1 ; } ; \
		fi  ;\
	done

changelog:
	#@rm -f ChangeLog
	#./mkchangelog.sh > ChangeLog

clean:
	rm -f *~ *.gz *.bz2

tag:
	@git tag -a -m "Tag as $(TAG)" -f $(TAG)
	@echo "Tagged as $(TAG)"

archive: clean check tag changelog
	@git archive --format=tar --prefix=$(PKGNAME)-$(VERSION)/ HEAD > $(PKGNAME)-$(VERSION).tar
	@mkdir -p $(PKGNAME)-$(VERSION)/
	@cp ChangeLog $(PKGNAME)-$(VERSION)/
	@tar --append -f $(PKGNAME)-$(VERSION).tar $(PKGNAME)-$(VERSION)
	@bzip2 -f $(PKGNAME)-$(VERSION).tar
	@rm -rf $(PKGNAME)-$(VERSION)
	@echo "The archive is at $(PKGNAME)-$(VERSION).tar.bz2"


version:
	@echo $(VERSION)

release:
	@echo $(RELEASE)

%.8: %.txt
	@mkdir -p $(dir $@)
	$(V) bin/txt2man -t $(basename $(notdir $<)) \
	-s 8 -v "System Manager's Manual" -r "Device Mapper Tools" $< > $@

