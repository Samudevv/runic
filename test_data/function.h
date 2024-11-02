#include <stdarg.h>

#define printf(x, y) return

void hello_world();

void foo(int a, int b, const char u);

static inline char bar(unsigned long long int);

void baz(struct { int a, b; } x);

const char *strcpy(const char *);

static inline void print_stuff(const char *msg) { printf("%s\n", msg); }
__attribute__((null))

void b();

void asm_func() __asm__("movl $5, %eax") __attribute__((null));

int a;

void eof() {}

void variadic_func(int a, va_list args);
