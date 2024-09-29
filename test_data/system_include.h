#include <also_my_system.h>
#include <my_system.h>
#include <third_party.h>

typedef int from_main;
typedef sysi from_other_system;

typedef struct {
  from_system b;
} main_struct;

main_struct ctx;

from_system part(from_system a, ant *b);
