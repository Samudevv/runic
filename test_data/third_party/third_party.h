typedef float ant;

struct feature_t {
  int caps;
  float times;
  int arr[5];
};

struct donkey_t {
  struct feature_t features;
  int (*oink)(float volume, float speed);
};
