PLAT_OS := $(shell uname)

BUILD_DIR := $(shell realpath ../../build)
ODIN_ROOT := $(shell dirname $(shell which odin))
ifeq ($(PLAT_OS), Darwin)
STBLIB := $(ODIN_ROOT)/vendor/stb/lib/darwin/stb_image.a
else
STBLIB := $(ODIN_ROOT)/vendor/stb/lib/stb_image.a
endif
ifeq ($(PLAT_OS), FreeBSD)
MAKE := gmake
else
MAKE := make
endif

default: run

$(BUILD_DIR)/olivec_example: olivec_example.odin olivec/olivec.odin $(STBLIB)
	odin build . -out:$@ -debug -error-pos-style:unix -extra-linker-flags=-L$(BUILD_DIR) -define:OLIVEC_STATIC=true

olivec/olivec.odin: $(BUILD_DIR)/libolivec.a rune.json
	$(BUILD_DIR)/runic_debug

$(BUILD_DIR)/libolivec.a: olive.c olivec_impl.c
	@mkdir -p $(BUILD_DIR)
	zig cc -o $(BUILD_DIR)/olivec_impl.c.o -c --std=c99 olivec_impl.c
	ar r $@ $(BUILD_DIR)/olivec_impl.c.o

$(STBLIB):
	$(MAKE) -C $(ODIN_ROOT)/vendor/stb/src

PHONY: clean run

run: $(BUILD_DIR)/olivec_example
	$(BUILD_DIR)/olivec_example

clean:
	rm -rf olivec/ $(BUILD_DIR)/libolivec.a $(BUILD_DIR)/olivec_impl.c.o