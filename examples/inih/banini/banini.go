package main

import (
	"fmt"
	"os"
	"strconv"
	"unsafe"

	ini "github.com/PucklaJ/banini/inih"
)

type Configuration struct {
	Version int
	Name    string
	Email   string
}

func Handler(user unsafe.Pointer, section, name, value ini.RunicString, lineno int32) int32 {
	pconfig := (*Configuration)(user)

	switch ini.ConstGoString(section) {
	case "protocol":
		switch ini.ConstGoString(name) {
		case "version":
			pconfig.Version, _ = strconv.Atoi(ini.ConstGoString(value))
		default:
			return 0
		}
	case "user":
		switch ini.ConstGoString(name) {
		case "name":
			pconfig.Name = ini.GoString(value)
		case "email":
			pconfig.Email = ini.GoString(value)
		default:
			return 0
		}
	default:
		return 0
	}

	return 1
}

func main() {
	if err := ini.LoadForeignLibrary(); err != nil {
		panic(err)
	}

	var config Configuration

	if ini.Parse("banin.ini", Handler, unsafe.Pointer(&config)) < 0 {
		fmt.Printf("Can't load 'banin.ini'\n")
		os.Exit(1)
	}

	fmt.Printf("'banin.ini': version=%d, name=\"%s\", email=\"%s\"\n", config.Version, config.Name, config.Email)

	if config.Version != 67 {
		fmt.Printf("Version is wrong!\n")
		os.Exit(1)
	}

	if config.Name != "bananananananananana" {
		fmt.Printf("Name is wrong!\n")
		os.Exit(1)
	}

	if config.Email != "yellow@banana.com" {
		fmt.Printf("Email is wrong!\n")
		os.Exit(1)
	}

	fmt.Printf("Everything is bananananananananananananananana... 🍌\n")
}
