# Runic

Bindings Generator and Intermediate Format for programming languages using the C-ABI.

The goal of this project is to allow the developer to freely choose which ever language they desire as long as that language can interact with the C-ABI.

For example if you would like to use odin in your project but also use a C library you would have a problem. You could either implement the whole library in odin, create bindings manually or look for an entirely different approach which lets you use another library. Therefore you are often bound to the language which you decide to use, which only gets intensified if the language is not that popular. Runic tries to fix this problem by creating an intermediate format from which every language can generate bindings from. Every language can also generate this intermediate format from itself to even allow bindings between languages that are not C.

## Supported Languages

| Language | From  |  To   |
| -------- | :---: | :---: |
| C        |   ✅   |   ✅   |
| Odin     |   ✅   |   ✅   |

## Usage

```console
runic [rune file]
```

Runic is configured through a **rune** file which is a json file that contains the language **from** which to generate a **runestone** and (if specified) the language **to** which to write bindings using the generated **runestone**. If no rune file is specified a `rune.json` file in the current directory is attempted to be opened.

A **runestone** is an intermediate format that contains all symbols and necessary types that are contained inside one library file (e.g. libfoo.a, libfoo.so, foo.lib, foo.dll etc.)

## Build

### Dependencies

First make sure that all submodules are checked out. Then following dependencies are required:

+ [odin](https://odin-lang.org)
+ [zig](https://ziglang.org) (*required as a preprocessor for C*)
+ [just](https://just.systems/)

Arch Linux: `sudo pacman -S --needed zig base-devel just` <br>
Ubuntu: `sudo apt install build-essential just`

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

+ [olivec](examples/olivec) <br> This example creates odin bindings to the rendering library [olive.c](https://github.com/tsoding/olive.c) and a program that uses said library to render an example image. Build it using:
  ```console
  just example olivec
  ```

+ [glew](examples/glew) <br> This example creates odin bindings to the [glew](https://glew.sourceforge.net/) library which is an OpenGL extension loading library. The example uses it to create a game of life implementation. Build it using:
  ```console
  just example glew
  ```

  **Dependencies**:
  + Arch Linux: `sudo pacman -S --needed glew glfw`
  + Ubuntu: `sudo apt install libglew-dev libglfw3-dev`
  + Windows: wget, 7zip (can be installed using `winget install wget 7zip` or `choco install wget 7zip`)

## Runestone

```ini
version = 0

[lib]
shared = libfoo.so
static = libfoo.a

[symbols]
func.foo1234 = #Void a #SInt32 #Attr Ptr 1 #AttrEnd b #SInt32 #Attr Ptr 1 #AttrEnd
func.output_print_name = #SInt32 output output #Attr Ptr 1 #AttrEnd
func.print = #Void var_args #Variadic
func.funcy = #RawPtr
var.foo_varZZXX6 = #Float32 #Attr Ptr 1 Arr 10 #AttrEnd
var.idx = #UInt64
var.counter = #UInt8

[remap]
foo = foo1234
foo_var = foo_varZZXX6

[alias]
oof = foo

[anonymous_types]
0 = #Struct desc str apple #UInt8
1 = #Struct x #SInt32 y #SInt32

[types]
i32 = #SInt32
str = #UInt8 #Attr Ptr 1 #AttrEnd
output = #Struct x #SInt32 y #SInt32 name str pear #Anon 0
output_flags = #Enum #SInt32 SHOWN 0 HIDDEN 1 OFF ARR_CAP ON "1+2"
numbers = #Float32 #Attr Arr ARR_SIZE #AttrEnd
transform = #Float64 #Attr ReadOnly Arr 4 ReadOnly Arr 4 WriteOnly #AttrEnd
outer = #Float32 #Attr Ptr 1 Arr 2 #AttrEnd
times = #SInt32 #Attr Arr "5*6/3*(8%9)" #AttrEnd
super_ptr = #Anon 1 #Attr Ptr 1 #AttrEnd

[methods]
output.print_name = output_print_name

[constants]
ARR_SIZE = 5 #Untyped
ARR_CAP = 20 #UInt64
APP_NAME = "Hello World" #SInt8 #Attr Ptr 1 #AttrEnd
LENGTH = 267.3450000000000273 #Float64
```

A runestone is a (modified) ini file containing information about the contents of one library file which can either be a static or a shared library. Thint to replace the C header files which are usually used to define the symbols of a library file. The format is meant to be easily parsable even if a parser is written from scratch.

## Rune

```json
{
  "version": 0,
  "from": {
    "language": "c",
    "static.linux": "libolivec.a",
    "static.windows": "olivec.lib",
    "headers": [
      "olive.c"
    ],
    "defines": {
      "OLIVECDEF": "extern"
    },
    "ignore": {
      "macros": [
        "OLIVE_C_",
        "OLIVEC_CANVAS_NULL"
      ]
    }
  },
  "to": {
    "language": "odin",
    "package": "olivec",
    "trim_prefix": {
      "functions": "olivec_",
      "types": "Olivec_",
      "constants": "OLIVEC_"
    },
    "out": "olivec/olivec.odin"
  }
}
```

This example rune file is used to generate the bindings of the olivec example. A rune file contains all configuration necessary to generate bindings or runestones. One rune consists of a from and a to section. Each section can either specify a runestone file or a configuration that generates a runestone or bindings respectively.
