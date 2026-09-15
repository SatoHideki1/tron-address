#ifndef MATCH_H
#define MATCH_H

#include <stddef.h>
#include <regex.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MATCH_NONE = 0,
    MATCH_PREFIX,
    MATCH_SUFFIX,
    MATCH_BOTH,
    MATCH_CONTAIN,
    MATCH_REGEX,
    MATCH_REPEATED_SUFFIX,
    MATCH_FILE
} match_mode_t;

typedef struct {
    char *pattern;
    int is_prefix; /* 1 = prefix, 0 = suffix */
} file_rule_t;

typedef struct {
    match_mode_t mode;
    char prefix[64];
    char suffix[64];
    char contain[64];
    char regex_str[256];
    int repeat_count;
    int ignore_case;

    /* Compiled regex */
    regex_t regex_comp;
    int regex_ready;

    /* Rule file entries */
    file_rule_t *file_rules;
    size_t file_rule_count;
} match_config_t;

/* Initialize matcher */
int match_init(match_config_t *cfg);

/* Free matcher resources */
void match_free(match_config_t *cfg);

/* Test if address matches configuration */
int match_address(const match_config_t *cfg, const char *address);

/* Validate configuration parameters (Base58 characters, lengths) */
int match_validate_config(match_config_t *cfg, char *err_buf, size_t err_buflen);

/* Load rule file (prefix/suffix list) */
int match_load_rule_file(match_config_t *cfg, const char *filepath);

#ifdef __cplusplus
}
#endif

#endif /* MATCH_H */
