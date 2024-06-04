typedef union {
  unsigned int zuz;
  signed int uzu;
} my_union;

union other_union {
  struct {
    float f;
    float g;
  } floaties;

  unsigned long long int inties;
};
