# Goals for future versions

+ C
  + To
    + [ ] Add build tag-like line to the top of the generated header. Maybe use `#error` if the platform differs.
+ Odin
  + To
    + [x] Make different 'add_libs' for shared and static
    + [ ] Generate constants always as "constants"
    + [ ] Add entry in the rune to configure the file names when generating multiple files.
    + [ ] Add entry to rune to always output multiple files (one per platform, one per cross runestone).
  + From
    + [ ] Implement Odin-specific types
      + [ ] Slice, dynamic array
      + [ ] Union
      + [ ] bit_set, bit_field
      + [ ] Struct alignment and packing
      + [ ] More complex constants (typed, expressions etc.)
    + [ ] Support extern system
      + [ ] Add field to define certain packages or collections as extern
+ [ ] Prettier and more useful logs
+ [ ] Better error messages
+ [x] Add `#Opaque` Type
