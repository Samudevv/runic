//go:build linux
package greatwave

import (
	"unsafe"
)

func LinuxGlobals() Array {
	return *(*Array)(unsafe.Pointer(runicPtrLinuxGlobals))
}

func SetLinuxGlobals(value Array) {
	*(*Array)(unsafe.Pointer(runicPtrLinuxGlobals)) = value
}

var (
	runicPtrLinuxGlobals uintptr
)

var (
	runicSymbolsLinux = [][2]any{
		{&runicPtrLinuxGlobals, "linux_globals"},
	}

	runicSymbolsWindows = [][2]any{}
)
