ODINC ?= odin
ODIN_FLAGS ?=\
	-vet-shadowing \
	-vet-unused \
	-vet-style \
	-warnings-as-errors \
	-error-pos-style:unix
ODIN_DEBUG_FLAGS ?= -debug
ODIN_RELEASE_FLAGS ?= -o:speed
BUILD_DIR := $(shell realpath ../../build)

game_of_life: $(BUILD_DIR)/game_of_life

$(BUILD_DIR)/game_of_life: gl/glew.odin game_of_life.odin
	$(ODINC) build . -out:$@ $(ODIN_FLAGS) $(ODIN_DEBUG_FLAGS) '-extra-linker-flags:-lEGL -lGL -lGLU -lOpenGL'

gl/glew.odin: $(BUILD_DIR)/glew.runestone.ini bindings.json
	$(BUILD_DIR)/runic_debug bindings.json

$(BUILD_DIR)/glew.runestone.ini: rune.json
	$(BUILD_DIR)/runic_debug rune.json

clean:
	rm -f $(BUILD_DIR)/game_of_life
	rm -f $(BUILD_DIR)/glew.runestone.ini
	rm -rf gl