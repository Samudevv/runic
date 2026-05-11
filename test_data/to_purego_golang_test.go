package greatwave

import (
	"errors"
	"runtime"
	"unsafe"

	"github.com/ebitengine/purego"
)

type MySizeType uint64
type Window struct {
	Name RunicString
	Width uint32
	Height uint32
}
type Array struct {
	Len MySizeType
	Cap MySizeType
	Els *uint32
}

var (
	CreateWindow func(name string, width uint32, height uint32) *Window
	CreateArray func(size MySizeType) Array
	ArrayAppend func(arr *Array, value uint32) Array
	LinuxGlobals Array
)

func LoadForeignLibrary() error {
	var runicLibraries = map[[2]string]string{
		{"any", "any"}: "libfoo.so",
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
		{&CreateWindow, "create_window"},
		{&CreateArray, "create_array"},
		{&ArrayAppend, "array_append"},

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


