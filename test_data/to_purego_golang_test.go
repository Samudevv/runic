package greatwave

import (
	"errors"
	"runtime"

	"github.com/ebitengine/purego"
)

type my_size_type uint64
type Window struct {
	name string
	width uint32
	height uint32
}
type Array struct {
	len my_size_type
	cap my_size_type
	els uint32
}

var (
	create_window func(name string, width uint32, height uint32) Window
	create_array func(size my_size_type) Array
	linux_globals Array
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

var (
	ErrNoLibraryForPlatform = errors.New("Current platform does not have a library")

	runicForeignLibrary uintptr
)

func runicRegisterSymbols() error {
	runicSymbols := [][2]any{
		{&create_window, "create_window"},
		{&create_array, "create_array"},
		{&linux_globals, "linux_globals"},
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


