# Goals for future versions

## 0.4 (?)

+ C
  + From
    + [ ] Overwrite types like `uint32_t` and `size_t` with their underlying types using macros
    + [ ] Use the clang flag `-nostdinc`
    + [ ] Generate directory which contains all of the std headers as empty files
  + To
    + [ ] Add build tag-like line to the top of the generated header. Maybe use `#error` if the platform differs.
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
+ [ ] Overwrite types (#Untyped means don't use the type at all)
+ [ ] Prettier and more useful logs
+ [ ] Better error messages
+ [ ] If requested, run formatter over generated code
+ [ ] Fix arena allocations of runestone. Make sure that the arena is always the same even if moved out of the scope
