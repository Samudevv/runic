typedef struct {
  int a;
  int b;
} spelling_t;

struct foo_t {
  spelling_t b;
};

inline void print_stuff(int a, int b) { int c = a + b; }
static inline const float **do_other_stuff(float c, float **d) {
  float e = e + **d;
}
inline spelling_t alphabet() { return spelling_t{}; }
inline struct foo_t japanese() { return foo_tert{}; }

struct foo_t chinese() {
  return foo_t {}
}