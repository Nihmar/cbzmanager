.PHONY: all build release test test-checks clean man install install-man pkg

PREFIX  ?= /usr/local
DESTDIR ?=
VERSION ?= 0.1.1

FPC_VERSION ?= $(shell fpc -iV 2>/dev/null || echo 3.2.2)
ARCH ?= x86_64-linux
FPC_UNITS ?= /usr/lib/fpc/$(FPC_VERSION)/units/$(ARCH)
LAZ_BASE ?= /usr/lib/lazarus

FPC_BASE_FU = \
  -Fu$(FPC_UNITS)/rtl \
  -Fu$(LAZ_BASE)/lcl/units/$(ARCH) \
  -Fu$(LAZ_BASE)/lcl/units/$(ARCH)/qt6 \
  -Fu$(LAZ_BASE)/components/lazutils/lib/$(ARCH) \
  -Fu$(LAZ_BASE)/packager/units/$(ARCH) \
  -Fu$(LAZ_BASE)/components/freetype/lib/$(ARCH) \
  -Fu$(FPC_UNITS)/fcl-web \
  -Fu$(FPC_UNITS)/fcl-net \
  -Fu$(FPC_UNITS)/openssl \
  -Fu$$HOME/.lazarus/lib/units/$(ARCH)/qt6

FPC_FLAGS = -MObjFPC -Scghi -O1 -gw3 -gl -l

all: build

# Debug build (default)
build:
	mkdir -p bin/debug/$(ARCH) obj/debug/$(ARCH)
	fpc $(FPC_FLAGS) \
	  $(FPC_BASE_FU) \
	  -Fusrc -Fulib \
	  -FEbin/debug/$(ARCH) -FUobj/debug/$(ARCH) \
	  -dLCL -dLCLqt6 \
	  cbzmanager.lpr

# Release build (mirrors .lpi Release mode: O3, smart link, strip, no debug)
release:
	mkdir -p bin/release/$(ARCH) obj/release/$(ARCH)
	fpc -MObjFPC -Scghi -O3 -XX -Xs -l \
	  $(FPC_BASE_FU) \
	  -Fusrc -Fulib \
	  -FEbin/release/$(ARCH) -FUobj/release/$(ARCH) \
	  -dLCL -dLCLqt6 \
	  cbzmanager.lpr

test-compile:
	mkdir -p bin/tests obj/tests
	fpc $(FPC_FLAGS) \
	  $(FPC_BASE_FU) \
	  -Fu$(FPC_UNITS)/fcl-fpcunit \
	  -Fu$(FPC_UNITS)/paszlib \
	  -Fusrc -Fulib \
	  -FEbin/tests -FUobj/tests \
	  -dLCL -dLCLqt6 \
	  tests/testrunner.pp

test: test-compile
	QT_QPA_PLATFORM=offscreen ./bin/tests/testrunner --all

test-compile-checks:
	mkdir -p bin/testchecks obj/testchecks
	fpc $(FPC_FLAGS) -Cr -Co -Ci -Ct -gh \
	  $(FPC_BASE_FU) \
	  -Fu$(FPC_UNITS)/fcl-fpcunit \
	  -Fu$(FPC_UNITS)/paszlib \
	  -Fusrc -Fulib \
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
	install -Dm755 bin/release/$(ARCH)/cbzmanager $(DESTDIR)/usr/bin/cbzmanager
	install -Dm644 man/cbzmanager.1 $(DESTDIR)/usr/share/man/man1/cbzmanager.1
	install -Dm644 pkg/cbzmanager.svg $(DESTDIR)/usr/share/icons/hicolor/scalable/apps/cbzmanager.svg
	install -Dm644 pkg/cbzmanager.desktop $(DESTDIR)/usr/share/applications/cbzmanager.desktop

install-man:
	install -Dm644 man/cbzmanager.1 $(DESTDIR)$(PREFIX)/share/man/man1/cbzmanager.1

# Build an Arch Linux package and install it via pacman
pkg: release
	cd pkg && sed "s/^pkgver=.*/pkgver=$(VERSION)/" PKGBUILD > PKGBUILD.tmp && mv PKGBUILD.tmp PKGBUILD && \
	rm -f cbzmanager-*.pkg.tar.zst && \
	makepkg -sf && sudo pacman -U --overwrite '*' cbzmanager-*.pkg.tar.zst

clean:
	rm -rf bin/tests obj/tests bin/testchecks obj/testchecks
