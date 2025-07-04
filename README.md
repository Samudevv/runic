# Runic

Bindings Generator and Intermediate Format for programming languages using the C-ABI.

**This project is heavily under development, therefore if you would like to use it, make sure to build directly from the master branch**

The goal of this project is to allow the developer to freely choose which ever language they desire as long as that language can interact with the C-ABI.

For example if you would like to use odin in your project but also use a C library you would have a problem. You could either implement the whole library in odin, create bindings manually or look for an entirely different approach which lets you use another library. Therefore you are often bound to the language which you decide to use, which only gets intensified if the language is not that popular. Runic tries to fix this problem by creating an intermediate format from which every language can generate bindings from. Every language can also generate this intermediate format from itself to even allow bindings between languages that are not C.

## Supported Languages

| Language | From | To  |
| -------- | :--: | :-: |
| C        |  ✅  | ✅  |
| Odin     |  ✅  | ✅  |

## Documentation

There is documentation available on the [wiki](https://github.com/Samudevv/runic/wiki).

## Usage

```console
	runic [rune] [--credits] [--version]
Flags:
	--rune <string>  | The rune configuration file to load
	                 |
	--credits        | Print credits to dependencies
	--version        | Print version and license information
```

Runic is configured through a **rune** file which is a yaml file that contains the language **from** which to generate a **runestone** and (if specified) the language **to** which to write bindings using the generated **runestone**. If no rune file is specified a `rune.yml` file in the current directory is attempted to be opened.

A **runestone** is an intermediate format that contains all symbols and necessary types that are contained inside one library file (e.g. libfoo.a, libfoo.so, foo.lib, foo.dll etc.)

## Build

### Dependencies

First make sure that all submodules are checked out. Then following dependencies are required:

- [odin](https://odin-lang.org)
- [just](https://just.systems/)
- [libclang](https://clang.llvm.org/docs/LibClang.html) (Confirmed Versions: 18, 19)
- [libyaml](https://github.com/yaml/libyaml)

Arch Linux: `sudo pacman -S --needed --noconfirm base-devel just clang18 libyaml` <br>
Ubuntu 24.04: `sudo apt install -y build-essential just libclang-18-dev libyaml-dev` <br>
Ubuntu 22.04: `sudo apt install -y build-essential libclang-dev libyaml-dev` <br> _On older Ubuntu systems `libclang-18-dev` does not exist, so the newest version should be installed. The package `just` also does not exist, but a statically linked executable can be downloaded directly from the releases page of the repository_

MacOS: `brew install llvm@19` _libyaml is already packaged into the odin library_ <br>
Windows: All dependencies are already provided for the `x86_64` architecture <br>

You may need to create a symlink manually called `libclang.so` that points to the correct library file.

### Linux

```console
just
```

This will build a release build of runic and write the resulting binary to `build/runic`

### Windows

```console
.\build.cmd
```

or

```console
just
```

This will build a release build of runic and write the resulting binary to `build\runic.exe`

## Examples

This repository contains some examples which show how the tool can be used.

- [olivec](examples/olivec) <br> This example creates odin bindings to the rendering library [olive.c](https://github.com/tsoding/olive.c) and a program that uses said library to render an example image. Build it using:
  ```console
  just example olivec
  ```

- [tiled](examples/tiled) <br> This example creates c bindings to [odin-tiled](https://github.com/SabeDoesThings/odin-tiled) and renders a tile map to a window and a ppm file. It depends on [SDL2](https://libsdl.org) and [SDL2_image](https://github.com/libsdl-org/SDL_image/tree/SDL2). Build and run it using:
  ```console
  # This creates an image file test_data/tiled.ppm
  just example tiled
  # To render to a window run
  just --justfile examples/tiled/justfile run
  ```

## Runestone

[Runestone Documentation](https://github.com/Samudevv/runic/wiki/Runestone)

```ini
version = 0

os = Linux
arch = x86_64

[lib]
shared = libfoo.so
static = libfoo.a

[symbols]
func.foo1234 = #Untyped a #SInt32 #Attr Ptr 1 #AttrEnd b #SInt32 #Attr Ptr 1 #AttrEnd
func.output_print_name = #SInt32 output output #Attr Ptr 1 #AttrEnd
func.print = #Untyped var_args #Variadic
func.funcy = #RawPtr
var.foo_varZZXX6 = #Float32 #Attr Ptr 1 Arr 10 #AttrEnd
var.idx = #UInt64
var.counter = #UInt8

[remap]
foo = foo1234
foo_var = foo_varZZXX6

[alias]
oof = foo

[types]
i32 = #SInt32
str = #UInt8 #Attr Ptr 1 #AttrEnd
anon_0 = #Struct desc str apple #UInt8
output = #Struct x #SInt32 y #SInt32 name str pear anon_0
output_flags = #Enum #SInt32 SHOWN 0 HIDDEN 1 OFF ARR_CAP ON "1+2"
numbers = #Float32 #Attr Arr ARR_SIZE #AttrEnd
transform = #Float64 #Attr ReadOnly Arr 4 ReadOnly Arr 4 WriteOnly #AttrEnd
outer = #Float32 #Attr Ptr 1 Arr 2 #AttrEnd
times = #SInt32 #Attr Arr "5*6/3*(8%9)" #AttrEnd
anon_1 = #Struct x #SInt32 y #SInt32
super_ptr = anon_1 #Attr Ptr 1 #AttrEnd

[methods]
output.print_name = output_print_name

[constants]
ARR_SIZE = 5 #Untyped
ARR_CAP = 20 #UInt64
APP_NAME = "Hello World" #SInt8 #Attr Ptr 1 #AttrEnd
LENGTH = 267.3450000000000273 #Float64
```

A runestone is a (modified) ini file containing information about the contents of one library file which can either be a static or a shared library. Meant to replace the C header files which are usually used to define the symbols of a library file. The format is meant to be easily parsable even if a parser is written from scratch.

## Rune

[Rune Documentation](https://github.com/Samudevv/runic/wiki/Rune)

```yaml
version: 0
platforms:
  - Linux x86_64
  - Macos x86_64
  - Windows x86_64
from:
  language: c
  static: libolivec.a
  static.windows: olivec.lib
  headers: olive.c
  defines:
    OLIVECDEF: "extern"
  ignore:
    constants:
      - OLIVE_C_
      - OLIVEC_CANVAS_NULL
to:
  language: odin
  package: olivec
  trim_prefix:
    functions: olivec_
    types: Olivec_
    constants: OLIVEC_
  no_build_tag: yes
  use_when_else: yes
  ignore_arch: yes
  out: "olivec/olivec.odin
```

This example rune file is used to generate the bindings of the olivec example. A rune file contains all configuration necessary to generate bindings or runestones. One rune consists of a from and a to section. Each section can either specify a runestone file or a configuration that generates a runestone or bindings respectively.
