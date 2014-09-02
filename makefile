.PHONY: all test

DMD = dmd
GDC = gdc
LDC = ldc2
SRC = src/main.d\
	src/stats.d\
	src/imports.d\
	src/highlighter.d\
	src/ctags.d\
	src/astprinter.d\
	src/outliner.d\
	src/symbol_finder.d\
	src/analysis/*.d\
	libdparse/src/std/*.d\
	libdparse/src/std/d/*.d\
	inifiled/source/*.d
INCLUDE_PATHS = -Ilibdparse/src
VERSIONS =
DEBUG_VERSIONS = -version=std_parser_verbose

all: dmdbuild
ldc: ldcbuild
gdc: gdcbuild

debug:
	${DMD} -g -ofdsc ${VERSIONS} ${DEBUG_VERSIONS} ${INCLUDE_PATHS} ${SRC}

dmdbuild:
	mkdir -p bin
	${DMD} -O -release -inline -ofbin/dscanner ${VERSIONS} ${INCLUDE_PATHS} ${SRC}
	rm -f bin/dscanner.o

gdcbuild:
	mkdir -p bin
	${GDC} -O3 -frelease -obin/dscanner ${VERSIONS} ${INCLUDE_PATHS} ${SRC}

ldcbuild:
	mkdir -p bin
	${LDC} -O5 -release -oq -of=bin/dscanner ${VERSIONS} ${INCLUDE_PATHS} ${SRC}

test:
	@./test.sh

clean:
	rm -rf dsc *.o
	rm -rf bin
	rm -f dscanner-report.json

report: all
	dscanner --report src > dscanner-report.json
	sonar-runner
