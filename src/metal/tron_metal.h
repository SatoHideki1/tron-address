#ifndef TRON_METAL_H
#define TRON_METAL_H

#include "../match.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Check if Metal GPU is supported on current system */
int tron_metal_is_supported(void);

/* Get the Metal GPU device name */
const char *tron_metal_get_device_name(void);

/* Start Metal GPU vanity address generation engine */
int tron_metal_start(const match_config_t *cfg,
                     int target_count,
                     const char *output_file,
                     int gpu_limit,
                     int quiet);

#ifdef __cplusplus
}
#endif

#endif /* TRON_METAL_H */
