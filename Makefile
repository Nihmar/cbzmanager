.PHONY: all build release test test-checks clean man install install-man pkg

PREFIX  ?= /usr/local
DESTDIR ?=
VERSION ?= 0.1.0

FPC_RTL   = /usr/lib/fpc/3.2.2/units/x86_64-linux
LAZ_BASE  = /usr/lib/lazarus
LAZ_UNITS = $(LAZ_BASE)/units/x86_64-linux
QT6_UNITS = $(LAZ_BASE)/lcl/units/x86_64-linux/qt6

UNIT_PATHS = \
  -Fu$(FPC_RTL)/rtl \
  -Fu$(LAZ_BASE)/lcl/units/x86_64-linux \
  -Fu$(QT6_UNITS) \
  -Fu$(LAZ_BASE)/components/lazutils/lib/x86_64-linux \
  -Fu$(LAZ_BASE)/packager/units/x86_64-linux \
  -Fu$(LAZ_BASE)/components/freetype/lib/x86_64-linux \
  -Fu$(FPC_RTL)/fcl-web \
  -Fu$(FPC_RTL)/openssl \
  -Fu$$HOME/.lazarus/lib/units/x86_64-linux/qt6 \
  -Fusrc -Fulib

all: build

# Debug build (default)
build:
	mkdir -p bin/debug/x86_64-linux obj/debug/x86_64-linux
	fpc -MObjFPC -Scghi -O1 -gw3 -gl -l \
	  $(UNIT_PATHS) \
	  -FEbin/debug/x86_64-linux -FUobj/debug/x86_64-linux \
	  -dLCL -dLCLqt6 \
	  cbzmanager.lpr

# Release build (mirrors .lpi Release mode: O3, smart link, strip, no debug)
release:
	mkdir -p bin/release/x86_64-linux obj/release/x86_64-linux
	fpc -MObjFPC -Scghi -O3 -XX -Xs -l \
	  $(UNIT_PATHS) \
	  -FEbin/release/x86_64-linux -FUobj/release/x86_64-linux \
	  -dLCL -dLCLqt6 \
	  cbzmanager.lpr

test-compile:
	mkdir -p bin/tests obj/tests
	fpc -MObjFPC -Scghi -O1 -gw3 -gl -l \
	  $(UNIT_PATHS) \
	  -Fu/usr/lib/fpc/3.2.2/units/x86_64-linux/fcl-fpcunit \
	  -Fu/usr/lib/fpc/3.2.2/units/x86_64-linux/paszlib \
	  -FEbin/tests -FUobj/tests \
	  -dLCL -dLCLqt6 \
	  tests/testrunner.pp

test: test-compile
	QT_QPA_PLATFORM=offscreen ./bin/tests/testrunner --all

test-compile-checks:
	mkdir -p bin/testchecks obj/testchecks
	fpc -MObjFPC -Scghi -O1 -gw3 -gl -l -Cr -Co -Ci -Ct -gh \
	  $(UNIT_PATHS) \
	  -Fu/usr/lib/fpc/3.2.2/units/x86_64-linux/fcl-fpcunit \
	  -Fu/usr/lib/fpc/3.2.2/units/x86_64-linux/paszlib \
	  -FEbin/testchecks -FUobj/testchecks \
	  -dLCL -dLCLqt6 \
	  tests/testrunner.pp

# Run the FPCUnit suite with the full debug profile (range checks, overflow
# checks, heaptrc) so memory errors that the release build tolerates are
# caught in CI instead of the user's session.
test-checks: test-compile-checks
	QT_QPA_PLATFORM=offscreen ./bin/testchecks/testrunner --all

man:
	@if command -v groff >/dev/null 2>&1; then \
	  groff -man -z man/cbzmanager.1 && \
	  echo "man page OK: man/cbzmanager.1"; \
	else \
	  echo "groff not found - skipping man page check"; \
	fi

install: release
	install -Dm755 bin/release/x86_64-linux/cbzmanager $(DESTDIR)/usr/bin/cbzmanager
	install -Dm644 man/cbzmanager.1 $(DESTDIR)/usr/share/man/man1/cbzmanager.1
	install -Dm644 pkg/cbzmanager.svg $(DESTDIR)/usr/share/icons/hicolor/scalable/apps/cbzmanager.svg
	install -Dm644 pkg/cbzmanager.desktop $(DESTDIR)/usr/share/applications/cbzmanager.desktop

install-man:
	install -Dm644 man/cbzmanager.1 $(DESTDIR)$(PREFIX)/share/man/man1/cbzmanager.1

# Build an Arch Linux package and install it via pacman
pkg: release
	cd pkg && makepkg -si

clean:
	rm -rf bin/tests obj/tests bin/testchecks obj/testchecks
