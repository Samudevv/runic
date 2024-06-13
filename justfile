set windows-shell := ['powershell.exe']

ODIN_FLAGS := (
  '-vet-shadowing ' +
  '-vet-unused ' +
  '-vet-style ' +
  '-warnings-as-errors ' +
  '-error-pos-style:unix ' +
  '-collection:root=. '
)
ODIN_DEBUG_FLAGS := '-debug'
ODIN_RELEASE_FLAGS := '-o:speed' + if os() == 'linux' {' -extra-linker-flags=-static'} else {''}

BUILD_DIR := 'build'
CREATE_BUILD_DIR := if os_family() == 'unix' {'mkdir -p "' + BUILD_DIR + '"'} else {'New-Item -Path "' + BUILD_DIR + '" -ItemType Directory -Force'}
EXE_EXT := if os_family() == 'unix' {''} else {'.exe'}

default: release
tools: showc cpp cppp
all: debug release tools test (example 'olivec') (example 'glew')

release ODIN_JOBS=num_cpus():
  @{{ CREATE_BUILD_DIR }}
  odin build . {{ ODIN_FLAGS }} -out:"{{ BUILD_DIR / 'runic' + EXE_EXT  }}" {{ ODIN_RELEASE_FLAGS }} -thread-count:{{ ODIN_JOBS }}

debug ODIN_JOBS=num_cpus():
  @{{ CREATE_BUILD_DIR }}
  odin build . {{ ODIN_FLAGS }} -out:"{{ BUILD_DIR / 'runic_debug' + EXE_EXT }}" {{ ODIN_DEBUG_FLAGS }} -thread-count:{{ ODIN_JOBS }}

test PACKAGE='.' ODIN_TESTS='' ODIN_JOBS=num_cpus(): (win_cat ODIN_JOBS)
  @{{ CREATE_BUILD_DIR }}
  odin test {{ PACKAGE }} {{ ODIN_FLAGS }} -all-packages -out:"{{ BUILD_DIR / 'runic_test' + EXE_EXT }}" {{ ODIN_DEBUG_FLAGS }} -thread-count:{{ ODIN_JOBS }} {{ if ODIN_TESTS == '' {''} else {'-test-name:' + ODIN_TESTS} }} -define:ODIN_TEST_THREADS=1

[unix]
win_cat ODIN_JOBS=num_cpus():

[windows]
win_cat ODIN_JOBS=num_cpus():
  @{{ CREATE_BUILD_DIR }}
  odin build test_data/win_cat.odin -file {{ ODIN_FLAGS }} -out:"{{ BUILD_DIR / 'win_cat.exe' }}" {{ ODIN_DEBUG_FLAGS }} -thread-count:{{ ODIN_JOBS }}

showc ODIN_JOBS=num_cpus():
  @{{ CREATE_BUILD_DIR }}
  odin build c/showc {{ ODIN_FLAGS }} -out:"{{ BUILD_DIR / 'showc' + EXE_EXT }}" {{ ODIN_RELEASE_FLAGS }} -thread-count:{{ ODIN_JOBS }}

cppp ODIN_JOBS=num_cpus():
  @{{ CREATE_BUILD_DIR }}
  odin build c/ppp {{ ODIN_FLAGS }} -out:"{{ BUILD_DIR / 'cppp' + EXE_EXT }}" {{ ODIN_RELEASE_FLAGS }} -thread-count:{{ ODIN_JOBS }}

cpp ODIN_JOBS=num_cpus():
  @{{ CREATE_BUILD_DIR }}
  odin build c/pp {{ ODIN_FLAGS }} -out:"{{ BUILD_DIR / 'cpp' + EXE_EXT }}" {{ ODIN_RELEASE_FLAGS }} -thread-count:{{ ODIN_JOBS }}

check TARGET='' ODIN_JOBS=num_cpus():
  odin check . {{ ODIN_FLAGS }} -thread-count:{{ ODIN_JOBS }} {{ if TARGET == '' {''} else {'-target:' + TARGET} }}

example EXAMPLE: debug
  @just --justfile "{{ 'examples' / EXAMPLE / 'justfile' }}"

[unix]
clean:
  rm -rf "{{ BUILD_DIR }}"
  @just --justfile examples/olivec/justfile clean
  @just --justfile examples/glew/justfile clean

[windows]
clean:
  if (Test-Path -Path "{{ BUILD_DIR }}") { Remove-Item -Path "{{ BUILD_DIR }}" -Recurse -Force -ErrorAction SilentlyContinue }
  @just --justfile examples/olivec/justfile clean