#define OLIVEC_IMPLEMENTATION
#define OLIVECDEF
#include "olive.c"

Olivec_Font export_olivec_default_font() { return olivec_default_font; }

#ifdef _WIN32
void __stack_chk_fail() {}
void __stack_chk_guard() {}
#endif