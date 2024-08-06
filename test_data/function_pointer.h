typedef void GLFWwindow;

void (*hello)();

unsigned long long int (*bye)(
    int a, char c, const _Bool x, struct {
      int a;
      int b;
    } s);

typedef void (*callback)(GLFWwindow *window, int key, int scancode, int action,
                         int mods);

extern void *(*get_proc_address)(const char *);

void (**hello_world)();

int (****const foo)();

void(*signal(int, void (*)(int)))(int);

typedef void (*const consty)(int a, int b);
