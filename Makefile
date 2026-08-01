.PHONY: all build test clean man install-man

PREFIX ?= /usr/local
DESTDIR ?=

all: build

build:
	fpc -MObjFPC -Scghi -O1 -gw3 -gl -l \
	  -Fu/usr/lib/fpc/3.2.2/units/x86_64-linux/rtl \
	  -Fu/usr/lib/lazarus/lcl/units/x86_64-linux \
	  -Fu/usr/lib/lazarus/lcl/units/x86_64-linux/qt6 \
	  -Fu/usr/lib/lazarus/components/lazutils/lib/x86_64-linux \
	  -Fu/usr/lib/lazarus/packager/units/x86_64-linux \
	  -Fu/usr/lib/lazarus/components/freetype/lib/x86_64-linux \
	  -Fu$$HOME/.lazarus/lib/units/x86_64-linux/qt6 \
	  -Fusrc -Fulib \
	  -FEbin/debug/x86_64-linux -FUobj/debug/x86_64-linux \
	  -dLCL -dLCLqt6 \
	  cbzmanager.lpr

test-compile:
	mkdir -p bin/tests obj/tests
	fpc -MObjFPC -Scghi -O1 -gw3 -gl -l \
	  -Fu/usr/lib/fpc/3.2.2/units/x86_64-linux/rtl \
	  -Fu/usr/lib/fpc/3.2.2/units/x86_64-linux/fcl-fpcunit \
	  -Fu/usr/lib/fpc/3.2.2/units/x86_64-linux/paszlib \
	  -Fu/usr/lib/lazarus/lcl/units/x86_64-linux \
	  -Fu/usr/lib/lazarus/lcl/units/x86_64-linux/qt6 \
	  -Fu/usr/lib/lazarus/components/lazutils/lib/x86_64-linux \
	  -Fu/usr/lib/lazarus/packager/units/x86_64-linux \
	  -Fu/usr/lib/lazarus/components/freetype/lib/x86_64-linux \
	  -Fu$$HOME/.lazarus/lib/units/x86_64-linux/qt6 \
	  -Fusrc -Fulib \
	  -FEbin/tests -FUobj/tests \
	  -dLCL -dLCLqt6 \
	  tests/testrunner.pp

test: test-compile
	QT_QPA_PLATFORM=offscreen ./bin/tests/testrunner --all

man:
	@if command -v groff >/dev/null 2>&1; then \
	  groff -man -z man/cbzmanager.1 && \
	  echo "man page OK: man/cbzmanager.1"; \
	else \
	  echo "groff not found - skipping man page check"; \
	fi

install-man:
	install -Dm644 man/cbzmanager.1 $(DESTDIR)$(PREFIX)/share/man/man1/cbzmanager.1

clean:
	rm -rf bin/tests obj/tests
