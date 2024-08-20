#include "unknown.h"

struct big_package {
  char data[128];
};

struct big_small {
  struct big_package b;
  small_package s;
};

union unific {
  struct big_package b;
  small_package s;
  struct {
    int a, b;
  } w;
  struct zuz {
    char a;
  } x;
};

typedef struct zuz wood;

extern struct {
  int a, b;
} packer;

extern struct big_package pack;
extern small_package bag;
extern const wood tree;