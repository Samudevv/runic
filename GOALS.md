# Goals for future versions

## 0.2 (End of July)

+ [x] MacOS support
+ [x] BSD support
+ [x] Make odin integers sizes based on platform and architecture
+ [x] Switch to yaml for rune file
+ [ ] Handle Any OS and Any Arch where possible
+ [ ] Add 32-Bit architectures

## 0.4 (End of August)

+ [ ] libclang as backend of C parser

## 0.4 (?)

+ C
  + To
    + [ ] Automatic forward declarations
  + From
    + [ ] Generate wrappers for static and inline functions and variables
+ Odin
  + From
    + [ ] Implement Odin-specific types
      + [ ] Slice, dynamic array
      + [ ] Union
      + [ ] bit_set, bit_field
      + [ ] Struct alignment and packing
      + [ ] More complex constants (typed, expressions etc.)
    + [ ] other calling conventions
      + [ ] odin
      + [ ] contextless
+ [ ] Add custom remaps and aliases in rune
+ [ ] Overwrite types (#Untyped means don't use the type at all)
+ [ ] Prettier and more useful logs
+ [ ] Better error messages
+ [ ] If requested, run formatter over generated code
+ [ ] complex bindings example (e.g. cairo)
