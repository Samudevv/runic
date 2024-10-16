# Goals for future versions

## 0.4 (?)

+ C
  + To
    + [ ] Automatic forward declarations
  + From
    + [x] Generate wrappers for static and inline functions and variables
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
+ [x] Add custom remaps and aliases in rune
+ [ ] Overwrite types (#Untyped means don't use the type at all)
+ [ ] Prettier and more useful logs
+ [ ] Better error messages
+ [ ] If requested, run formatter over generated code
+ [x] complex bindings example (e.g. cairo) -> odin-wayland
+ [x] Complex overwrites for struct, union, function pointers
+ [x] Perform overwrite and ignore in main package
