set windows-shell := ['powershell.exe']

YAML_STATIC := if os() == 'linux' {
  'false'
} else if os() == 'windows' {
  'true'
} else if os() == 'macos' {
  if arch() == 'x86_64' {
    'true'
  } else {
    'false'
  }
} else {
  'false'
}
YAML_STATIC_DEBUG := if os() == 'windows' {
  'true'
} else {
  'false'
}

EXTRA_LINKER_FLAGS := if os() == 'macos' {
  '-extra-linker-flags:"-L' + shell('brew --prefix llvm@18') + '/lib"'
} else {
  ''
}

ODIN_FLAGS := (
  '-vet-shadowing ' +
  '-vet-unused ' +
  '-vet-style ' +
  '-warnings-as-errors ' +
  '-error-pos-style:unix ' +
  '-collection:root=. ' +
  '-collection:shared=shared ' +
  EXTRA_LINKER_FLAGS
)
ODIN_DEBUG_FLAGS := '-debug -define:YAML_STATIC=' + YAML_STATIC_DEBUG
ODIN_RELEASE_FLAGS := (
  '-o:speed ' +
  '-define:YAML_STATIC=' + YAML_STATIC
)

BUILD_DIR := 'build'
EXE_EXT := if os_family() == 'unix' {''} else {'.exe'}

default: release
tools: showc cpp cppp
all: debug release tools test (example 'olivec')

release ODIN_JOBS=num_cpus(): (make-directory BUILD_DIR)
  odin build . {{ ODIN_FLAGS }} -out:"{{ BUILD_DIR / 'runic' + EXE_EXT  }}" {{ ODIN_RELEASE_FLAGS }} -thread-count:{{ ODIN_JOBS }}

debug ODIN_JOBS=num_cpus(): (make-directory BUILD_DIR)
  odin build . {{ ODIN_FLAGS }} -out:"{{ BUILD_DIR / 'runic_debug' + EXE_EXT }}" {{ ODIN_DEBUG_FLAGS }} -thread-count:{{ ODIN_JOBS }}

test PACKAGE='.' ODIN_TESTS='' ODIN_JOBS=num_cpus(): (make-directory BUILD_DIR)
  odin test {{ PACKAGE }} {{ ODIN_FLAGS }} {{ if PACKAGE == '.' { '-all-packages' } else { '' } }} -out:"{{ BUILD_DIR / 'runic_test' + EXE_EXT }}" {{ ODIN_DEBUG_FLAGS }} -thread-count:{{ ODIN_JOBS }} {{ if ODIN_TESTS == '' {''} else {'-define:ODIN_TEST_NAMES=' + ODIN_TESTS} }} -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false

[linux]
test_windows_obj PACKAGE='.' ODIN_TESTS='' ODIN_JOBS=num_cpus(): (make-directory BUILD_DIR)
  -odin test {{ PACKAGE }} {{ ODIN_FLAGS }} -target:windows_amd64 {{ if PACKAGE == '.' { '-all-packages' } else { '' } }} -out:"{{ BUILD_DIR / 'runic_test.exe' }}" {{ ODIN_DEBUG_FLAGS }} -thread-count:{{ ODIN_JOBS }} {{ if ODIN_TESTS == '' {''} else {'-define:ODIN_TEST_NAMES=' + ODIN_TESTS} }} -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false

[linux]
test_windows_link:
    printf 'void __chkstk() {}\nvoid __security_cookie() {}\nvoid __security_check_cookie() {}\nvoid __GSHandlerCheck() {}\nvoid _RTC_CheckStackVars() {}\nvoid _RTC_InitBase() {}\nvoid _RTC_UninitUse() {}\nvoid _RTC_Shutdown() {}' > "{{ BUILD_DIR / 'chkstk.c' }}"
    x86_64-w64-mingw32-gcc -o "{{ BUILD_DIR / 'runic_test.exe' }}" "{{ BUILD_DIR / 'runic_test.obj' }}" -Lshared/libclang/lib/windows/x86_64/ -Lshared/yaml/lib/windows/x86_64/ -llibclang -lyaml -lsynchronization -lntdll "{{ BUILD_DIR / 'chkstk.c' }}" 
    ln -srf shared/libclang/lib/windows/x86_64/libclang.dll "{{ BUILD_DIR / 'libclang.dll' }}"

[linux]
test_windows_run:
    WINEDEBUG=-all wine "{{ BUILD_DIR / 'runic_test.exe' }}"

[linux]
test_windows COMPILE='n' LINK='y' PACKAGE='.' ODIN_TESTS='""' ODIN_JOBS=num_cpus():
    @{{ if COMPILE == 'y' { 'just test_windows_obj ' + PACKAGE + ' ' + ODIN_TESTS + ' ' + ODIN_JOBS } else {''} }}
    @{{ if LINK == 'y' { 'just test_windows_link' } else {''} }}
    @just test_windows_run

[unix]
win_cat ODIN_JOBS=num_cpus():

[windows]
win_cat ODIN_JOBS=num_cpus(): (make-directory BUILD_DIR)
  odin build test_data/win_cat.odin -file {{ ODIN_FLAGS }} -out:"{{ BUILD_DIR / 'win_cat.exe' }}" -thread-count:{{ ODIN_JOBS }}

showc ODIN_JOBS=num_cpus(): (make-directory BUILD_DIR)
  odin build c/showc {{ ODIN_FLAGS }} -out:"{{ BUILD_DIR / 'showc' + EXE_EXT }}" {{ ODIN_DEBUG_FLAGS }} -thread-count:{{ ODIN_JOBS }}

cppp ODIN_JOBS=num_cpus(): (make-directory BUILD_DIR)
  odin build c/ppp {{ ODIN_FLAGS }} -out:"{{ BUILD_DIR / 'cppp' + EXE_EXT }}" {{ ODIN_RELEASE_FLAGS }} -thread-count:{{ ODIN_JOBS }}

cpp ODIN_JOBS=num_cpus(): (make-directory BUILD_DIR)
  odin build c/pp {{ ODIN_FLAGS }} -out:"{{ BUILD_DIR / 'cpp' + EXE_EXT }}" {{ ODIN_RELEASE_FLAGS }} -thread-count:{{ ODIN_JOBS }}

check PACKAGE='.' TARGET='' ODIN_JOBS=num_cpus():
  odin check {{ PACKAGE }} {{ ODIN_FLAGS }} -thread-count:{{ ODIN_JOBS }} {{ if TARGET == '' {''} else {'-target:' + TARGET} }}

example EXAMPLE: debug
  @just --justfile "{{ 'examples' / EXAMPLE / 'justfile' }}" example

ARCH := if arch() == 'aarch64' { 'arm64' } else { arch() }
[windows]
package: release (make-directory BUILD_DIR / 'package')
  Copy-Item -Path "{{ BUILD_DIR / 'runic.exe' }}" -Destination "{{ BUILD_DIR / 'package' }}" -Force
  Copy-Item -Path "{{ justfile_directory() / 'shared/libclang/lib/windows' / ARCH / 'libclang.dll' }}" -Destination "{{ BUILD_DIR / 'package' }}" -Force
  Copy-Item -Path "{{ justfile_directory() / 'shared/libclang/README.md' }}" -Destination "{{ BUILD_DIR / 'package/libclang-LICENSE.md' }}" -Force
  Copy-Item -Path "{{ justfile_directory() / 'shared/yaml/README.md' }}" -Destination "{{ BUILD_DIR / 'package/libyaml-LICENSE.md' }}" -Force
  Compress-Archive -Path "{{ BUILD_DIR / 'package/*' }}" -DestinationPath "{{ BUILD_DIR / 'runic.windows-' + ARCH + '.zip' }}"

[unix]
clean:
  rm -rf "{{ BUILD_DIR }}" \
  test_data/write_to_handle \
  test_data/bindings.* \
  test_data/macros.*.h \
  test_data/*_runestone.ini \
  test_data/foozy/foozy.h
  @just --justfile examples/olivec/justfile clean

[windows]
clean:
  if (Test-Path -Path "{{ BUILD_DIR }}") { Remove-Item -Path "{{ BUILD_DIR }}" -Recurse -Force -ErrorAction SilentlyContinue }
  if (Test-Path -Path 'test_data/write_to_handle') { Remove-Item -Path 'test_data/write_to_handle' -Recurse -Force -ErrorAction SilentlyContinue }
  if (Test-Path -Path 'test_data/bindings.h') { Remove-Item -Path 'test_data/bindings.h' -Recurse -Force -ErrorAction SilentlyContinue }
  if (Test-Path -Path 'test_data/bindings.odin') { Remove-Item -Path 'test_data/bindings.odin' -Recurse -Force -ErrorAction SilentlyContinue }
  if (Test-Path -Path 'test_data/macros.pp.h') { Remove-Item -Path 'test_data/macros.pp.h' -Recurse -Force -ErrorAction SilentlyContinue }
  if (Test-Path -Path 'test_data/macros.ppp.h') { Remove-Item -Path 'test_data/macros.ppp.h' -Recurse -Force -ErrorAction SilentlyContinue }
  if (Test-Path -Path 'test_data/macros.ppp-pp.h') { Remove-Item -Path 'test_data/macros.ppp-pp.h' -Recurse -Force -ErrorAction SilentlyContinue }
  if (Test-Path -Path 'test_data/example_runestone.ini') { Remove-Item -Path 'test_data/example_runestone.ini' -Recurse -Force -ErrorAction SilentlyContinue }
  if (Test-Path -Path 'test_data/generate_runestone.ini') { Remove-Item -Path 'test_data/generate_runestone.ini' -Recurse -Force -ErrorAction SilentlyContinue }
  @just --justfile examples/olivec/justfile clean

[unix]
make-directory DIR:
  @mkdir -p "{{ DIR }}"

[windows]
make-directory DIR:
  @New-Item -Path "{{ DIR }}" -ItemType Directory -Force | Out-Null
