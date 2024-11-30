#define INCLUDE_CHILD 15

struct below_t;

int a;
int b;
const char *xyz;

typedef void (*callback_proc)(int a, void *user_data);

struct below_t {
  char a;
  char b;
};
