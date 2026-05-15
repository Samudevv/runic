/**************************************************************/
/* Public library functions                                   */
/**************************************************************/

// Load the dynamic library and all symbols
func LoadForeignLibrary() error {
	for _, runicPlatform := range runicPlatforms {
		runicLibraryName, runicLibraryNameOk := runicLibraries[runicPlatform]
		if !runicLibraryNameOk {
			continue
		}
		runicLibrary, runicLibraryErr := purego.Dlopen(runicLibraryName, purego.RTLD_NOW|purego.RTLD_GLOBAL)
		if runicLibraryErr != nil {
			return runicLibraryErr
		}
		runicForeignLibrary = runicLibrary
	}

	if runicForeignLibrary == 0 {
		return ErrNoLibraryForPlatform
	}

	for _, runicSomeSymbols := range runicAllSymbols {
		if err := runicRegisterSymbols(runicSomeSymbols); err != nil {
			return err
		}
	}

	return nil
}

// Unload the library and clean up all resources
func UnloadForeignLibrary() error {
	err := purego.Dlclose(runicForeignLibrary)
	runicForeignLibrary = 0
	return err
}

// Safe. Creates a copy of a C string and returns a go string
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

// Unsafe. Only use this function if the underlying C string does not change
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

/**************************************************************/
/* Internal functions                                         */
/**************************************************************/

type RunicString *uint8

var (
	ErrNoLibraryForPlatform = errors.New("Current platform does not have a library")

	runicForeignLibrary uintptr

	runicPlatforms = [][2]string{
		{runtime.GOOS, runtime.GOARCH},
		{runtime.GOOS, "any"},
		{"any", runtime.GOARCH},
		{"any", "any"},
	}
)

func runicRegisterSymbols(runicSymbolsParam [][2]any) error {
	for _, runicEntry := range runicSymbolsParam {
		runicSym, runicSymErr := purego.Dlsym(runicForeignLibrary, runicEntry[1].(string))
		if runicSymErr != nil {
			return runicSymErr
		}

		if runicUintptr, runicIsUintptr := runicEntry[0].(*uintptr); runicIsUintptr {
			*runicUintptr = runicSym
		} else {
			purego.RegisterFunc(runicEntry[0], runicSym)
		}
	}

	return nil
}
