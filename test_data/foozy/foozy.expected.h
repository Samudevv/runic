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

typedef struct hooty_tooty {
    struct hooty_tooty* child;
} hooty_tooty;

typedef struct hooty_shmooty {
    char*              b;
    struct hooty_tooty c;
} hooty_shmooty;

typedef struct booty_treasure {
    float                a;
    double               b;
    struct hooty_shmooty sh;
} booty_treasure;

typedef struct booty_treasure_slice {
    struct booty_treasure* data;
    int64_t                length;
} booty_treasure_slice;

typedef struct booty_treasure_slice typey_type;
typedef int64_t typeid;

typedef struct typeid_slice {
    typeid* data;
    int64_t length;
} typeid_slice;

typedef struct typeid_slice type_typey;

typedef struct runtime_Allocator {
    void* procedure;
    void* data;
} runtime_Allocator;

typedef struct booty_treasure_dynamic_array {
    struct booty_treasure*   data;
    int64_t                  length;
    int64_t                  capacity;
    struct runtime_Allocator allocator;
} booty_treasure_dynamic_array;

typedef struct booty_treasure_dynamic_array tüp_töp;

typedef struct typeid_dynamic_array {
    typeid*                  data;
    int64_t                  length;
    int64_t                  capacity;
    struct runtime_Allocator allocator;
} typeid_dynamic_array;

typedef struct typeid_dynamic_array töp_tüp;

typedef struct maybe_int {
    _Bool   ok;
    int64_t value;
} maybe_int;

typedef struct maybe_int mäybe;

typedef struct anon_0 {
    int64_t           x;
    unsigned __int128 y;
} anon_0;

typedef struct maybe_anon_0 {
    _Bool         ok;
    struct anon_0 value;
} maybe_anon_0;

typedef struct maybe_anon_0 möybe;

typedef struct maybe_booty_treasure {
    _Bool                 ok;
    struct booty_treasure value;
} maybe_booty_treasure;

typedef struct maybe_booty_treasure müybe;

typedef enum booty_boots {
    long_ones  =   0,
    small_ones =   1,
    wide_ones  =   2,
} booty_boots;

typedef union bar_union_values {
    int_ptr          v0;
    multi_int        v1;
    multi_int_ptr    v2;
    int_multi_ptr    v3;
    super_multi      v4;
    arr_ptr          v5;
    complex_ptr      v6;
    enum booty_boots v7;
} bar_union_values;

typedef struct bar_union {
    uint8_t                tag;
    union bar_union_values values;
} bar_union;

typedef uint8_t booty_bit_set_boots;
typedef booty_bit_set_boots booty_small_bit_set;
typedef uint32_t booty_bit_field_u32;
typedef booty_bit_field_u32 booty_large_bit_field;
typedef int32_t booty_boot_int;
typedef booty_boot_int booty_bit_set_boots_boot_int;
typedef booty_bit_set_boots_boot_int booty_booties;
typedef int64_t c_int64_t;

typedef struct booty_boot_int_slice {
    booty_boot_int* data;
    int64_t         length;
} booty_boot_int_slice;

typedef struct booty_boot_int_slice booty_large_slice;

typedef struct f64_slice {
    double* data;
    int64_t length;
} f64_slice;

typedef struct f64_slice booty_small_slice;

typedef union booty_large_union_values {
    int64_t        v0;
    uint32_t       v1;
    booty_boot_int v2;
} booty_large_union_values;

typedef struct booty_large_union {
    uint8_t                        tag;
    union booty_large_union_values values;
} booty_large_union;

typedef struct i32_slice {
    int32_t* data;
    int64_t  length;
} i32_slice;

typedef struct string {
    uint8_t* data;
    int64_t  length;
} string;

typedef struct booty_anon_1 {
    int64_t          id;
    struct string    first_name;
    struct string    last_name;
    enum booty_boots shoe;
} booty_anon_1;

typedef booty_boot_int (* booty_callback)(const struct booty_anon_1 order);
typedef struct pointed_cycle* cycle_pointer;

typedef struct pointed_cycle {
    cycle_pointer* data;
} pointed_cycle;

typedef int32_t sausage;

#define Weißwurst    ((sausages)  0)
#define Bratwurst    ((sausages)  1)
#define Käsekrainer  ((sausages) 69)
#define Frankfurter  ((sausages)  5)
#define Räucherwurst ((sausages)  6)
typedef int64_t sausages;

typedef struct sausage_foo {
    sausage  s;
    sausages type;
} sausage_foo;

typedef struct sausage_foo foo_sausage;

typedef struct my_foo {
    int8_t   x;
    uint64_t y;
} my_foo;

typedef union your_foo {
    uint32_t x;
    int32_t  y;
} your_foo;

typedef struct anon_2 {
    int64_t z;
} anon_2;

typedef struct anon_3 {
    int64_t       y;
    struct anon_2 cba;
} anon_3;

typedef struct nested {
    int64_t       x;
    struct anon_3 abc;
} nested;

typedef enum pants {
    trousers   =   0,
    skirt      =   1,
    pantalones =   2,
} pants;

typedef struct int_slice {
    int64_t* data;
    int64_t  length;
} int_slice;

typedef struct int_slice_slice {
    struct int_slice* data;
    int64_t           length;
} int_slice_slice;

typedef struct int_slice_slice_slice {
    struct int_slice_slice* data;
    int64_t                 length;
} int_slice_slice_slice;

typedef struct int_slice_slice_slice mega_int_slice;

typedef struct mega_int_slice_array_7_array_6_array_5_pointer_pointer_pointer_slice {
    mega_int_slice (****data)[5][6][7];
    int64_t        length;
} mega_int_slice_array_7_array_6_array_5_pointer_pointer_pointer_slice;

typedef struct mega_int_slice_array_7_array_6_array_5_pointer_pointer_pointer_slice super_int_slice;

typedef struct u8_pointer_pointer_pointer_array_5_slice {
    uint8_t*** (*data)[5];
    int64_t    length;
} u8_pointer_pointer_pointer_array_5_slice;

typedef struct u8_pointer_pointer_pointer_array_5_slice_slice {
    struct u8_pointer_pointer_pointer_array_5_slice* data;
    int64_t                                          length;
} u8_pointer_pointer_pointer_array_5_slice_slice;

typedef struct u8_pointer_pointer_pointer_array_5_slice_slice_slice {
    struct u8_pointer_pointer_pointer_array_5_slice_slice* data;
    int64_t                                                length;
} u8_pointer_pointer_pointer_array_5_slice_slice_slice;

typedef struct u8_pointer_pointer_pointer_array_5_slice_slice_slice_dynamic_array {
    struct u8_pointer_pointer_pointer_array_5_slice_slice_slice* data;
    int64_t                                                      length;
    int64_t                                                      capacity;
    struct runtime_Allocator                                     allocator;
} u8_pointer_pointer_pointer_array_5_slice_slice_slice_dynamic_array;

typedef struct u8_pointer_pointer_pointer_array_5_slice_slice_slice_dynamic_array_dynamic_array {
    struct u8_pointer_pointer_pointer_array_5_slice_slice_slice_dynamic_array* data;
    int64_t                                                                    length;
    int64_t                                                                    capacity;
    struct runtime_Allocator                                                   allocator;
} u8_pointer_pointer_pointer_array_5_slice_slice_slice_dynamic_array_dynamic_array;

typedef struct u8_pointer_pointer_pointer_array_5_slice_slice_slice_dynamic_array_dynamic_array_dynamic_array {
    struct u8_pointer_pointer_pointer_array_5_slice_slice_slice_dynamic_array_dynamic_array* data;
    int64_t                                                                                  length;
    int64_t                                                                                  capacity;
    struct runtime_Allocator                                                                 allocator;
} u8_pointer_pointer_pointer_array_5_slice_slice_slice_dynamic_array_dynamic_array_dynamic_array;

typedef struct u8_pointer_pointer_pointer_array_5_slice_slice_slice_dynamic_array_dynamic_array_dynamic_array confusing_type;
typedef struct runtime_Allocator my_allocator;
typedef void intrinsics_objc_object;
typedef intrinsics_objc_object my_obj;
typedef int64_t my_great_int;
typedef unsigned __int128 beans[128];
typedef uint16_t bit_field_u16;
typedef bit_field_u16 simple_bf;
typedef int32_t bit_field_i32_array_5[5];
typedef bit_field_i32_array_5 array_bf;
typedef my_great_int bit_field_my_great_int_array_2[2];
typedef bit_field_my_great_int_array_2 other_array_bf;
typedef booty_boot_int bit_field_booty_boot_int;
typedef bit_field_booty_boot_int package_bf;
typedef booty_boot_int bit_field_booty_boot_int_array_50[50];
typedef bit_field_booty_boot_int_array_50 other_package_bf;
typedef beans bit_field_beans;
typedef bit_field_beans bean_plantation;

typedef struct multi_foo_result {
    int64_t c;
    int64_t d;
} multi_foo_result;

typedef struct anon_4 {
    int64_t a;
    int64_t b;
} anon_4;

typedef union anon_5 {
    uint32_t x;
    int32_t  y;
} anon_5;

typedef struct i64_slice {
    int64_t* data;
    int64_t  length;
} i64_slice;

typedef struct string_slice {
    struct string* data;
    int64_t        length;
} string_slice;

typedef struct runtime_Logger {
    void*    procedure;
    void*    data;
    uint64_t lowest_level;
    uint16_t options;
} runtime_Logger;

typedef struct runtime_Random_Generator {
    void* procedure;
    void* data;
} runtime_Random_Generator;

typedef struct runtime_Context {
    struct runtime_Allocator        allocator;
    struct runtime_Allocator        temp_allocator;
    void*                           assertion_failure_proc;
    struct runtime_Logger           logger;
    struct runtime_Random_Generator random_generator;
    void*                           user_ptr;
    int64_t                         user_index;
    void*                           _internal;
} runtime_Context;

typedef struct int_dynamic_array {
    int64_t*                 data;
    int64_t                  length;
    int64_t                  capacity;
    struct runtime_Allocator allocator;
} int_dynamic_array;

typedef struct booty_boot_int_dynamic_array {
    booty_boot_int*          data;
    int64_t                  length;
    int64_t                  capacity;
    struct runtime_Allocator allocator;
} booty_boot_int_dynamic_array;

typedef struct booty_boot_int_dynamic_array booty_small_array;

typedef struct any {
    void*  data;
    typeid id;
} any;

typedef struct f32_dynamic_array {
    float*                   data;
    int64_t                  length;
    int64_t                  capacity;
    struct runtime_Allocator allocator;
} f32_dynamic_array;

typedef struct f32_dynamic_array booty_large_array;
typedef uint8_t bit_set_pants;
typedef uint16_t bit_set_languages;

#define english  ((languages)  0)
#define german   ((languages)  1)
#define japanese ((languages)  2)
#define chinese  ((languages)  3)
#define dutch    ((languages)  4)
#define greek    ((languages)  5)
#define hindi    ((languages)  6)
#define urdu     ((languages)  7)
#define latin    ((languages)  8)
#define sanskrit ((languages)  9)
typedef int64_t languages;

typedef uint64_t bit_set_languages_u64;
typedef int32_t polyglot_int;
typedef polyglot_int bit_set_languages_polyglot_int;

#define one   ((anon_bit_set_enum_6)  0)
#define two   ((anon_bit_set_enum_6)  1)
#define three ((anon_bit_set_enum_6)  2)
typedef int64_t anon_bit_set_enum_6;

typedef uint8_t bit_set_anon_bit_set_enum_6;

#define four ((anon_bit_set_enum_7)  0)
#define five ((anon_bit_set_enum_7)  1)
#define six  ((anon_bit_set_enum_7)  2)
typedef int64_t anon_bit_set_enum_7;

typedef int8_t bit_set_anon_bit_set_enum_7_i8;
typedef uint32_t bit_set_range_26;
typedef uint8_t bit_set_range_2_to_5;
typedef uint8_t bit_set_booty_boots;
typedef booty_boot_int bit_set_booty_boots_booty_boot_int;

extern booty_small_bit_set bar_value;
extern booty_large_bit_field baz_value;
extern booty_booties faz_value;
extern super_multi your_var;
extern float* mumu;
extern uint64_t (* error_callback)(const int64_t err);
extern bit_set_pants multi_pant;
extern bit_set_languages polyglot;
extern bit_set_languages polyglot1;
extern bit_set_languages polyglot2;
extern bit_set_languages_u64 special_polyglot;
extern bit_set_languages_u64 another_special_polyglot;
extern bit_set_languages_polyglot_int very_polyglot;
extern bit_set_anon_bit_set_enum_6 numbers;
extern bit_set_anon_bit_set_enum_7_i8 underlying_numbers;
extern bit_set_range_26 abc_bitset;
extern bit_set_range_2_to_5 number_range;
extern bit_set_booty_boots boot_options;
extern bit_set_booty_boots_booty_boot_int foo_booties;

extern char* bar(const char* msg, const int64_t result);
extern char* parse_int(const c_int64_t value, const booty_large_slice v1, const booty_small_slice v2);
extern void do_alloc(const struct booty_treasure ctx, const struct booty_large_union types);
extern uint64_t process_orders(const struct i32_slice orders, const booty_callback cb);
extern int64_t foo(const int64_t a, const int64_t b);
extern struct multi_foo_result multi_foo(const int64_t a, const int64_t b);
extern uint32_t super_foo(const struct my_foo a);
extern void print_pants(const enum pants a);
extern void print_sausages(const sausages b);
extern union anon_5 multi_sausage(struct anon_4**const over);
extern void print_slice(const struct i64_slice s);
extern void add_slice(struct i64_slice*const s, const int64_t a);
extern void multi_add_slice(const struct i64_slice (*ss)[5], const int64_t a);
extern struct string cstring_to_string(const char* str);
extern void print_strings(const struct string_slice str);
extern struct runtime_Context odin_default_context();
extern void append_five(struct int_dynamic_array*const arr, const int64_t value);
extern booty_large_array make_large_array(const booty_small_array s, const typeid t, const struct any a);

#define foozy_bar bar
#define foozy_parse_int parse_int
#define foozy_do_alloc do_alloc
#define foozy_process_orders process_orders
#define foozy_foo foo
#define foozy_multi_foo multi_foo
#define foozy_super_foo super_foo
#define foozy_print_pants print_pants
#define foozy_print_sausages print_sausages
#define foozy_multi_sausage multi_sausage
#define foozy_print_slice print_slice
#define foozy_add_slice add_slice
#define foozy_multi_add_slice multi_add_slice
#define foozy_cstring_to_string cstring_to_string
#define foozy_print_strings print_strings
#define foozy_odin_default_context odin_default_context
#define foozy_append_five append_five
#define foozy_make_large_array make_large_array

