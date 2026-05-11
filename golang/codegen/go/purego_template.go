package main

import (
	"errors"
	"runtime"

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

func main() {
	if err := LoadForeignLibrary(); err != nil {
		panic(err)
	}

	Puts("Calling C from Go without Cgo!")
}
