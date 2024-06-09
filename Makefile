ODINC = odin
ODIN_JOBS ?= 1
ODIN_TESTS ?= nil
ODIN_FLAGS ?=  \
	-vet-shadowing \
	-vet-unused \
	-vet-style \
	-warnings-as-errors \
	-error-pos-style:unix \
	-collection:root=.
ODIN_DEBUG_FLAGS ?= -debug
ODIN_RELEASE_FLAGS ?= -o:speed -extra-linker-flags=-static

ifneq ($(ODIN_TESTS), nil)
	ODIN_TEST_FLAG := -test-name:$(ODIN_TESTS)
	_DMY := $(shell rm -f build/*_test*)
endif

ERRORS_DS := $(patsubst %.odin, build/d/%.d, $(wildcard errors/*.odin))
INI_DS := $(patsubst %.odin, build/d/%.d, $(wildcard ini/*.odin))
EXEC_DS := $(patsubst %.odin, build/d/%.d, $(wildcard exec/*.odin))
OM_DS := $(patsubst %.odin, build/d/%.d, $(wildcard ordered_map/*.odin))
RUNIC_DS := $(patsubst %.odin, build/d/%.d, $(wildcard runic/*.odin)) $(INI_DS) $(ERRORS_DS) $(OM_DS)
C_PARSER_DS := $(patsubst %.odin, build/d/%.d, $(wildcard c/parser/*.odin)) $(ERRORS_DS) $(EXEC_DS)
C_SHOWC_DS := $(patsubst %.odin, build/d/%.d, $(wildcard c/showc/*.odin)) $(C_PARSER_DS)
C_PP_DS := $(patsubst %.odin, build/d/%.d, $(wildcard c/pp/*.odin)) $(C_PARSER_DS)
C_PPP_DS := $(patsubst %.odin, build/d/%.d, $(wildcard c/ppp/*.odin)) $(C_PARSER_DS)
C_CODEGEN_DS := $(patsubst %.odin, build/d/%.d, $(wildcard c/codegen/*.odin)) $(RUNIC_DS) $(C_PARSER_DS)
ODIN_CODEGEN_DS := $(patsubst %.odin, build/d/%.d, $(wildcard odin/codegen/*.odin)) $(RUNIC_DS)
MAIN_DS := $(patsubst %.odin, build/d/%.d, $(wildcard *.odin)) $(RUNIC_DS) $(C_CODEGEN_DS) $(ODIN_CODEGEN_DS) $(ERRORS_DS)

default: release
all: build/runic_test tools release debug example/olivec example/glew
tools: build/showc build/cpp build/cppp
debug: build/runic_debug
release: build/runic

.PHONY: clean test example check

build/showc: $(C_SHOWC_DS)
	@mkdir -p $(shell dirname $@)
	$(ODINC) build c/showc $(ODIN_FLAGS) -out:$@ $(ODIN_RELEASE_FLAGS) -thread-count:$(ODIN_JOBS)

build/cppp: $(C_PPP_DS)
	@mkdir -p $(shell dirname $@)
	$(ODINC) build c/ppp $(ODIN_FLAGS) -out:$@ $(ODIN_RELEASE_FLAGS) -thread-count:$(ODIN_JOBS)

build/cpp: $(C_PP_DS)
	@mkdir -p $(shell dirname $@)
	$(ODINC) build c/pp $(ODIN_FLAGS) -out:$@ $(ODIN_RELEASE_FLAGS) -thread-count:$(ODIN_JOBS)

build/runic_debug: $(MAIN_DS)
	@mkdir -p $(shell dirname $@)
	$(ODINC) build . $(ODIN_FLAGS) -out:$@ $(ODIN_DEBUG_FLAGS) -thread-count:$(ODIN_JOBS)

build/runic: $(MAIN_DS)
	@mkdir -p $(shell dirname $@)
	$(ODINC) build . $(ODIN_FLAGS) -out:$@ $(ODIN_RELEASE_FLAGS) -thread-count:$(ODIN_JOBS)
	strip -s $@

build/runic_test: $(MAIN_DS)
	@mkdir -p $(shell dirname $@)
	$(ODINC) test . $(ODIN_FLAGS) -all-packages -out:$@ $(ODIN_DEBUG_FLAGS) -thread-count:$(ODIN_JOBS) $(ODIN_TEST_FLAG)

clean:
	rm -rf build
	make -C examples/olivec clean
	make -C examples/glew clean

test: build/runic_test
	build/runic_test

check:
	$(ODINC) check . $(ODIN_FLAGS) -thread-count:$(ODIN_JOBS)

check_macos:
	$(ODINC) check . $(ODIN_FLAGS) -thread-count:$(ODIN_JOBS) -target:darwin_amd64

example/olivec: debug
	@make -C examples/olivec

example/glew: debug
	@make -C examples/glew

build/d/%.d: %.odin
	@mkdir -p $(shell dirname $@)
	@touch $@
