# Goals for future versions

+ C
  + To
    + [ ] Add build tag-like line to the top of the generated header. Maybe use `#error` if the platform differs.
  + From
    + [ ] If field widths are encountered write out a warning and generate those types as byte arrays
+ Odin
  + To
    + [x] Generate `#Untyped` types as `Untyped` which is a non-existing type to force the user to fix those types
    + [ ] Fix build tag
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
