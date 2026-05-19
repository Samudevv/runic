//go:build windows
package greatwave

import (
	"unsafe"
)

type Window_Win32 struct {
	Name RunicString
	Width uint32
	Height uint32
	Win32id uint
}

var (
	CreateWindowWin32 func(NAME string, WIDTH uint32, HEIGHT uint32) *Window_Win32
)

func WindowsGlobals() Array {
	return *(*Array)(unsafe.Pointer(runicPtrWindowsGlobals))
}

func SetWindowsGlobals(value Array) {
	*(*Array)(unsafe.Pointer(runicPtrWindowsGlobals)) = value
}

var (
	runicPtrWindowsGlobals uintptr
)

var (
	runicSymbolsWindows = [][2]any{
		{&CreateWindowWin32, "create_window_win32"},
		{&runicPtrWindowsGlobals, "windows_globals"},
	}

	runicSymbolsLinux = [][2]any{}
)
