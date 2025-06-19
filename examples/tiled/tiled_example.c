#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SDL_MAIN_HANDLED
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>

#include "tiled.h"

// Linked from stb_image.a etc.
extern uint8_t *stbi_load(const char *filename, int *x, int *y,
                          int *channels_in_file, int desired_channels);

struct string cstr_to_string(const char *str) {
  struct string s = {
      .data = (uint8_t *)(str),
      .length = (int64_t)strlen(str),
  };
  return s;
}

char *string_to_cstr(const struct string str) {
  if (str.length == 0) {
    return "null";
  }

  // We don't care about leaks here
  char *buf = (char *)malloc(str.length + 1);
  memcpy(buf, str.data, str.length);
  buf[str.length] = '\0';
  return buf;
}

int main(int args, char *argv[]) {
  _Bool headless = 0;
  if (args >= 2) {
    if (strcmp(argv[1], "--headless") == 0) {
      headless = 1;
    }
  }

  const struct string map_file_name = cstr_to_string("tilemap.json");

  const struct tiled_Map map = tiled_parse_tilemap(map_file_name);

  printf("Map version=%.3f width=%d height=%d layers=%ld\n", map.version,
         map.width, map.height, map.layers.length);

  struct tiled_Tileset_slice tilesets = map.tilesets;
  SDL_Texture **tileset_textures =
      (SDL_Texture **)malloc(sizeof(void *) * map.tilesets.length);

  for (int64_t i = 0; i < tilesets.length; i++) {
    const int32_t firstgid = tilesets.data[i].firstgid;
    struct tiled_Tileset tileset = tiled_parse_tileset(tilesets.data[i].source);
    printf("Tileset %ld name=\"%s\" image=\"%s\" tilewidth=%d tileheight=%d "
           "firstgid=%d\n",
           i, string_to_cstr(tileset.name), string_to_cstr(tileset.image),
           tileset.tilewidth, tileset.tileheight, firstgid);

    tileset.firstgid = firstgid;
    tilesets.data[i] = tileset;
  }

  const int32_t scale = 2;
  const int32_t window_width = map.width * map.tilewidth * scale;
  const int32_t window_height = map.height * map.tileheight * scale;

  SDL_Init(SDL_INIT_VIDEO);
  IMG_Init(IMG_INIT_PNG);

  SDL_Window *w = SDL_CreateWindow(
      "Tiled", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, window_width,
      window_height, headless ? SDL_WINDOW_HIDDEN : SDL_WINDOW_SHOWN);
  SDL_Renderer *r = SDL_CreateRenderer(w, -1, SDL_RENDERER_ACCELERATED);

  for (int64_t i = 0; i < tilesets.length; i++) {
    SDL_Surface *surface = IMG_Load(string_to_cstr(tilesets.data[i].image));
    SDL_Texture *texture = SDL_CreateTextureFromSurface(r, surface);
    SDL_FreeSurface(surface);
    tileset_textures[i] = texture;
  }

  SDL_Texture *target_texture =
      SDL_CreateTexture(r, SDL_PIXELFORMAT_BGRA8888, SDL_TEXTUREACCESS_TARGET,
                        window_width, window_height);
  SDL_SetRenderTarget(r, target_texture);

  SDL_SetRenderDrawColor(r, 255, 255, 255, 255);
  SDL_RenderClear(r);

  for (int64_t layer_idx = 0; layer_idx < map.layers.length; layer_idx++) {
    struct tiled_Layer layer = map.layers.data[layer_idx];
    printf("Layer %ld width=%d height=%d offsetx=%.1f offsety=%.1f data=%ld\n",
           layer_idx, layer.width, layer.height, layer.offsetx, layer.offsety,
           layer.data.length);
    for (int32_t x_idx = 0; x_idx < layer.width; x_idx++) {
      for (int32_t y_idx = 0; y_idx < layer.height; y_idx++) {
        const int32_t data_idx = y_idx * layer.width + x_idx;

        const SDL_Rect dst = {
            .x = ((int32_t)layer.offsetx + x_idx * map.tilewidth) * scale,
            .y = ((int32_t)layer.offsety + y_idx * map.tileheight) * scale,
            .w = map.tilewidth * scale,
            .h = map.tileheight * scale,
        };

        const int32_t tile_gid = layer.data.data[data_idx];

        for (int64_t tileset_idx = 0; tileset_idx < tilesets.length;
             tileset_idx++) {
          struct tiled_Tileset tileset = tilesets.data[tileset_idx];
          if (tileset.firstgid <= tile_gid) {
            const int32_t tile_idx = tile_gid - tileset.firstgid;
            const int32_t tile_x = tile_idx % tileset.columns;
            const int32_t tile_y = tile_idx / tileset.columns;

            const int32_t tile_pixel_x = tile_x * tileset.tilewidth;
            const int32_t tile_pixel_y = tile_y * tileset.tileheight;

            const SDL_Rect src = {
                .x = tile_pixel_x,
                .y = tile_pixel_y,
                .w = tileset.tilewidth,
                .h = tileset.tileheight,
            };
            SDL_RenderCopy(r, tileset_textures[tileset_idx], &src, &dst);

            break;
          }
        }
      }
    }
  }

  if (!headless) {
    SDL_SetRenderTarget(r, NULL);
    SDL_RenderCopy(r, target_texture, NULL, NULL);
    SDL_RenderPresent(r);
  }

  SDL_SetRenderTarget(r, target_texture);
  uint8_t *pixels = (uint8_t *)malloc(window_width * window_height * 4);
  if (SDL_RenderReadPixels(r, NULL, SDL_PIXELFORMAT_BGRA8888, pixels,
                           4 * window_width) != 0) {
    fprintf(stderr, "failed to read pixels: %s", SDL_GetError());
    exit(1);
  }
  SDL_SetRenderTarget(r, NULL);

  FILE *ppm_file = fopen("../../test_data/tiled.ppm", "w");

  fprintf(ppm_file, "P6\n%d %d\n255\n", window_width, window_height);

  for (int32_t y = 0; y < window_width; y++) {
    for (int32_t x = 0; x < window_height; x++) {
      fwrite(&pixels[4 * window_width * y + x * 4 + 1], 3, 1, ppm_file);
    }
  }

  fclose(ppm_file);

  if (!headless) {
    int running = 1;
    while (running) {
      SDL_Event e;
      while (SDL_PollEvent(&e)) {
        switch (e.type) {
        case SDL_QUIT:
          running = 0;
          break;
        }
      }
    }
  }

  SDL_DestroyRenderer(r);
  SDL_DestroyWindow(w);
  IMG_Quit();
  SDL_Quit();

  // Check for correctness of image
  printf("Checking correctness ...\n");

  int expected_width, expected_height, expected_channels;
  uint8_t *expected_pixels =
      stbi_load("../../test_data/tiled.expected.png", &expected_width,
                &expected_height, &expected_channels, 4);
  if (expected_pixels == NULL) {
    fprintf(stderr, "failed to load tiled.expected.png\n");
    return 1;
  }

  if (expected_width != window_width) {
    fprintf(stderr, "width: %d != %d\n", window_width, expected_width);
    return 1;
  }
  if (expected_height != window_height) {
    fprintf(stderr, "height: %d != %d\n", window_height, expected_height);
    return 1;
  }

  for (int32_t x = 0; x < window_width; x++) {
    for (int32_t y = 0; y < window_height; y++) {
      const uint8_t p_r = pixels[y * window_width * 4 + x * 4 + 1];
      const uint8_t p_g = pixels[y * window_width * 4 + x * 4 + 2];
      const uint8_t p_b = pixels[y * window_width * 4 + x * 4 + 3];
      const uint8_t p_a = pixels[y * window_width * 4 + x * 4 + 0];

      const uint8_t ex_r = expected_pixels[y * window_width * 4 + x * 4 + 0];
      const uint8_t ex_g = expected_pixels[y * window_width * 4 + x * 4 + 1];
      const uint8_t ex_b = expected_pixels[y * window_width * 4 + x * 4 + 2];
      const uint8_t ex_a = expected_pixels[y * window_width * 4 + x * 4 + 3];

      const int32_t d_r = (int32_t)p_r - (int32_t)ex_r;
      const int32_t d_g = (int32_t)p_g - (int32_t)ex_g;
      const int32_t d_b = (int32_t)p_b - (int32_t)ex_b;
      const int32_t d_a = (int32_t)p_a - (int32_t)ex_a;

      if (d_r < -10 || d_r > 10 || d_g < -10 || d_g > 10 || d_b < -10 ||
          d_b > 10 || d_a < -10 || d_a > 10) {
        fprintf(stderr, "Pixel[%d][%d] 0x%X%X%X%X != 0x%X%X%X%X\n", x, y, p_r,
                p_g, p_b, p_a, ex_r, ex_g, ex_b, ex_a);
        return 1;
      }
    }
  }

  // Here we care about deallocating, I guess.
  free(expected_pixels);
  free(pixels);

  return 0;
}