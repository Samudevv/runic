BUILD_DIR := $(shell realpath ../../build)
ODIN_ROOT := $(shell dirname $(shell which odin))
STBLIB := $(ODIN_ROOT)/vendor/stb/lib/stb_image.a

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
	CC='gcc' make -C $(ODIN_ROOT)/vendor/stb/src

PHONY: clean run

run: $(BUILD_DIR)/olivec_example
	$(BUILD_DIR)/olivec_example

clean:
	rm -rf olivec/ $(BUILD_DIR)/libolivec.a $(BUILD_DIR)/olivec_impl.c.o $(BUILD_DIR)/libstb_image.a $(BUILD_DIR)/std_image.o