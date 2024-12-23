# Goals for future versions

+ Wrapper
  + [x] Make more multi platform: Separate files for each platform
  + [x] Automatically add output header files to headers of `from` with field `add_out_header_to_from`
+ C
  + To
    + [ ] Add build tag-like line to the top of the generated header. Maybe use `#error` if the platform differs.
  + From
    + [ ] Improve macro parsing
        + [x] Parse strings as strings
        + [ ] Try to remove parenthesis
+ Odin
  + To
    + [ ] Make different 'add_libs' for shared and static
    + [ ] Generate constants always as "constants"
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
+ [x] Change `ignore.macros` to `ignore.constants`
+ [ ] Add `#Opaque` Type
