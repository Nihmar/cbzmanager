.PHONY: all build test clean

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
	./bin/tests/testrunner --all

clean:
	rm -rf bin/tests obj/tests
