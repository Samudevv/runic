#pragma once

#include <stdint.h>

#define FOO_VALUE 5
static const char* FOO_VALUE_STR = "5";
static const char* FOO_VALUE_LONG_STR = "five";
#define FOO_FLOAT 5.5999999999999996

struct pointed_cycle;

typedef int64_t* int_ptr;
typedef int64_t multi_int[10];
typedef int64_t (*multi_int_ptr)[10];
typedef int64_t* int_multi_ptr[10];
typedef double** super_multi[10][20][30][40][50];
typedef int64_t (*arr_ptr)[14];
typedef int64_t*** (***(*(*(***complex_ptr)[13][14])[15])[18])[17];
typedef int64_t c_int64_t;
typedef struct hooty_tooty {
struct hooty_tooty* child;
} hooty_tooty;
typedef struct hooty_shmooty {
char* b;
struct hooty_tooty c;
} hooty_shmooty;
typedef struct booty_treasure {
float a;
double b;
struct hooty_shmooty sh;
} booty_treasure;
typedef struct pointed_cycle* cycle_pointer;
typedef struct pointed_cycle {
cycle_pointer* data;
} pointed_cycle;
typedef int32_t sausage;
#define Weißwurst ((sausages)0)
#define Bratwurst ((sausages)1)
#define Käsekrainer ((sausages)69)
#define Frankfurter ((sausages)5)
#define Räucherwurst ((sausages)6)
typedef int64_t sausages;
typedef struct sausage_foo {
sausage s;
sausages type;
} sausage_foo;
typedef struct sausage_foo foo_sausage;
typedef struct my_foo {
int8_t x;
uint64_t y;
} my_foo;
typedef union your_foo {
uint32_t x;
int32_t y;
} your_foo;
typedef struct anon_0 {
int64_t z;
} anon_0;
typedef struct anon_1 {
int64_t y;
struct anon_0 cba;
} anon_1;
typedef struct nested {
int64_t x;
struct anon_1 abc;
} nested;
typedef enum pants {
trousers = 0,
skirt = 1,
pantalones = 2,
} pants;
typedef struct multi_foo_result {
int64_t c;
int64_t d;
} multi_foo_result;
typedef struct anon_2 {
int64_t a;
int64_t b;
} anon_2;
typedef union anon_3 {
uint32_t x;
int32_t y;
} anon_3;

extern super_multi your_var;
extern float* mumu;
extern uint64_t (* error_callback)(const int64_t err);

extern char* bar(const char* msg, const int64_t result);
extern char* parse_int(const c_int64_t value);
extern void do_alloc(const struct booty_treasure ctx);
extern int64_t foo(const int64_t a, const int64_t b);
extern struct multi_foo_result multi_foo(const int64_t a, const int64_t b);
extern uint32_t super_foo(const struct my_foo a);
extern void print_pants(const enum pants a);
extern void print_sausages(const sausages b);
extern union anon_3 multi_sausage(struct anon_2**const over);

#define foozy_bar bar
#define foozy_parse_int parse_int
#define foozy_do_alloc do_alloc
#define foozy_foo foo
#define foozy_multi_foo multi_foo
#define foozy_super_foo super_foo
#define foozy_print_pants print_pants
#define foozy_print_sausages print_sausages
#define foozy_multi_sausage multi_sausage

