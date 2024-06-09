PLAT_OS := $(shell uname)

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
ifeq ($(PLAT_OS), Linux)
LINK_FLAGS := -lEGL -lGL -lGLU -lOpenGL
else ifeq ($(PLAT_OS), Darwin)
LINK_FLAGS := -L$(brew --prefix glew)/lib -framework OpenGL
else ifeq ($(PLAT_OS), FreeBSD)
LINK_FLAGS := -lGL
endif

game_of_life: $(BUILD_DIR)/game_of_life

$(BUILD_DIR)/game_of_life: gl/glew.odin game_of_life.odin
	$(ODINC) build . -out:$@ $(ODIN_FLAGS) $(ODIN_DEBUG_FLAGS) "-extra-linker-flags:$(LINK_FLAGS)"

gl/glew.odin: $(BUILD_DIR)/glew.runestone.ini bindings.json
	$(BUILD_DIR)/runic_debug bindings.json

$(BUILD_DIR)/glew.runestone.ini: rune.json $(BUILD_DIR)/GL
	$(BUILD_DIR)/runic_debug rune.json

ifeq ($(PLAT_OS), Darwin)
$(BUILD_DIR)/GL:
	ln -s $(shell brew --prefix glew)/include/GL $@
else
$(BUILD_DIR)/GL:
	ln -s /usr/include/GL $@
endif

clean:
	rm -f $(BUILD_DIR)/game_of_life
	rm -f $(BUILD_DIR)/glew.runestone.ini
	rm -rf gl