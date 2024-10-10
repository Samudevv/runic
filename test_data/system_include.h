#include <also_my_system.h>
#include <my_system.h>
#include <third_party.h>

struct feature_t;

typedef int from_main;
typedef sysi from_other_system;

typedef struct {
  from_system b;
} main_struct;

main_struct ctx;

from_system part(from_system a, ant *b);

char *make_feature(struct feature_t *feature);

struct donkey_t new_donkey();
