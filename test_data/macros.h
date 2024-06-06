#pragma once

#define glCreateProgram GLEW_GET_FUNC(__glewCreateProgram)

#define A 1
#define B 2
#define C 3

#ifdef _WIN32
#define ODIN_WINDOWS
#else
#define ODIN_POSIX
#endif

#ifdef ODIN_WINDOWS
#define PLAT windows
#else
#define PLAT posix
#endif

#if PLAT == posix
int posix_func(int a, int b);
#elif PLAT == windows
int windows_func(int a, int b);
#else
int unknown_func(int a, int b);
#endif

#ifdef ODINC
void odin_compiler(const char a);
#endif

#define GLEW_GET_FUNC(x) x

#define glClearColor GLEW_GET_FUNC(__glewClearColor)

#define SUPER_FUNC(x, y, z) printf("x=%s y=%s z=%s\n", x, y, z)

#define DO_VAR DO_STUFF("Hello", "World", "Bye")

// clang-format off
#define DO_STUFF_2(b, c) (FIRST = b, SECOND= c)
#define DO_STUFF(a, b, c) (ZERO =a, DO_STUFF_2(b, c))
// clang-format on

// clang-format off
#define MULTI_VAR PRINT(x + y, y + x) PRINT1(z + x, y + z) PRINT0(x, z) PRINT3(x,u,i)
#define ALSO_VAR PRINT(a + PRINT(a,PRINT(u,i)), b)
#define PRINT(x, y) printf(x, y)
#define PRINT1(x, y) sprintf(x, y)
// clang-format on

#define REC_VAR REC_FUNC(value)
#define REC_FUNC(x) (RECY + x)
#define RECY 5

// clang-format off
#define SLASHY   COUNT 1 \
  2 \
  3 \
  4
// clang-format on

void __glewCreateProgram();
void __glewClearColor();
