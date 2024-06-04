typedef enum {
  A,
  B,
  C,
} abc_enum;

enum cba_enum { C, B, A };

enum constants {
  X = 1,
  Y = 5,
  Z = 8,
  W = -7,
  Apple = 789,
  Banana = 90.8,
  Calculate = (70 * 4 + 9) / 6 % 7,
};

enum { Hello, World } banana;

struct apple {
  int x;
  enum { left, right } direction;
  int a;
};
