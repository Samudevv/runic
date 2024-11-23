typedef struct {
  int *restrict a;
  volatile int b;
  int c;
  const unsigned long long int yzg;
} abc_t;

struct my_struct {
  unsigned x : 5;
  long long y : 5 * 6 + 3;
};

struct byte_array {
  int x : 8;
  long y : 16;
  unsigned int b : 24;
};

struct wl_output;

typedef struct _sszu_ {
  volatile float x;
} ss_t;

typedef struct {
  struct {
    int a;
    int b;
    struct {
      const char str;
    } x;
  } window;
} wl_context;
