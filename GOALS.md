# Goals for future versions

+ Wrapper
  + [x] Add `from_compiler_flags` to import the compiler flags from `from`
    + [x] Add `includedirs`, `defines`, `flags` fields which get added on top of the `from_compiler_flags`
  + [ ] Add `load_all_includes`
  + [ ] Make more multi platform: Separate files for each platform
  + [ ] Bonus: Add make files (nmake on windows) which compile the wrapper (field `gen_make_files`)
    + [ ] Set name of generated library `out_library` (static only)
  + [ ] Automatically add output header files to headers of `from` with field `add_out_header_to_from`
+ C
  + To
    + [ ] Add build tag-like line to the top of the generated header. Maybe use `#error` if the platform differs.
  + From
    + [x] If field widths are encountered write out a warning and generate those types as byte arrays
    + [x] Add `forward_decl_to_rawptr`. Put forward declarations into separate list and then add them as types if there implementation is not in `Runestone.types`. Probably also need to add the source of it.
+ Odin
  + To
    + [x] Generate `#Untyped` types as `Untyped` which is a non-existing type to force the user to fix those types
    + [x] Fix build tag
    + [x] Fix auto multi pointer to generate for the outer most array
    + [x] Add `add_libs` field to add additional libraries that should be linked
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
