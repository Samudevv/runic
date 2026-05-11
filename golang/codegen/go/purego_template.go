package main

import (
	"errors"
	"runtime"
	"unsafe"

	"github.com/ebitengine/purego"
)

type LibCType int

var (
	Puts func(string)
)

func LoadForeignLibrary() error {
	var runicLibraries = map[[2]string]string{
		{"linux", "amd64"}: "libc.so.6",
	}

	runicRuntimePlatform := [2]string{runtime.GOOS, runtime.GOARCH}
	runicPlatform := runicRuntimePlatform
	runicLibraryName, runicLibraryNameOk := runicLibraries[runicPlatform]
	if !runicLibraryNameOk {
		runicPlatform[1] = "any"
		runicLibraryName, runicLibraryNameOk = runicLibraries[runicPlatform]
	}
	if !runicLibraryNameOk {
		runicPlatform[0] = "any"
		runicPlatform[1] = runicRuntimePlatform[1]
		runicLibraryName, runicLibraryNameOk = runicLibraries[runicPlatform]
	}
	if !runicLibraryNameOk {
		runicPlatform[0] = "any"
		runicPlatform[1] = "any"
		runicLibraryName, runicLibraryNameOk = runicLibraries[runicPlatform]
	}
	if !runicLibraryNameOk {
		return ErrNoLibraryForPlatform
	}

	runicLibrary, runicLibraryErr := purego.Dlopen(runicLibraryName, purego.RTLD_NOW|purego.RTLD_GLOBAL)
	if runicLibraryErr != nil {
		return runicLibraryErr
	}

	runicForeignLibrary = runicLibrary

	return runicRegisterSymbols()
}

func UnloadForeignLibrary() error {
	return purego.Dlclose(runicForeignLibrary)
}

/**************************************************************/
/* Internal functions                                         */
/**************************************************************/

type RunicString *uint8

var (
	ErrNoLibraryForPlatform = errors.New("Current platform does not have a library")

	runicForeignLibrary uintptr
)

func runicRegisterSymbols() error {
	runicSymbols := [][2]any{
		{&Puts, "puts"},
	}

	for _, runicEntry := range runicSymbols {
		runicSym, runicSymErr := purego.Dlsym(runicForeignLibrary, runicEntry[1].(string))
		if runicSymErr != nil {
			return runicSymErr
		}
		purego.RegisterFunc(runicEntry[0], runicSym)
	}

	return nil
}

func GoString(str RunicString) string {
	if str == nil {
		return ""
	}

	var strLen int
	ptr := uintptr(unsafe.Pointer(str))
	for {
		c := *(*uint8)(unsafe.Pointer(ptr))
		if c == 0 {
			break
		}

		strLen += 1
		ptr += unsafe.Sizeof(*str)
	}

	slc := unsafe.Slice(str, strLen)
	return string(slc)
}

func ConstGoString(str RunicString) string {
	if str == nil {
		return ""
	}

	var strLen int
	ptr := uintptr(unsafe.Pointer(str))
	for {
		c := *(*uint8)(unsafe.Pointer(ptr))
		if c == 0 {
			break
		}

		strLen += 1
		ptr += unsafe.Sizeof(*str)
	}

	return unsafe.String((*byte)(unsafe.Pointer(str)), strLen)
}

func main() {
	if err := LoadForeignLibrary(); err != nil {
		panic(err)
	}

	Puts("Calling C from Go without Cgo!")
}
