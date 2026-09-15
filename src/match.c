#include "match.h"
#include "tron.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

static int case_cmp(char a, char b, int ignore_case) {
    if (ignore_case) {
        return tolower((unsigned char)a) - tolower((unsigned char)b);
    }
    return (unsigned char)a - (unsigned char)b;
}

static int str_prefix_match(const char *str, const char *prefix, int ignore_case) {
    size_t plen = strlen(prefix);
    if (strlen(str) < plen) return 0;
    for (size_t i = 0; i < plen; i++) {
        if (case_cmp(str[i], prefix[i], ignore_case) != 0) {
            return 0;
        }
    }
    return 1;
}

static int str_suffix_match(const char *str, const char *suffix, int ignore_case) {
    size_t slen = strlen(str);
    size_t suflen = strlen(suffix);
    if (slen < suflen) return 0;
    const char *start = str + slen - suflen;
    for (size_t i = 0; i < suflen; i++) {
        if (case_cmp(start[i], suffix[i], ignore_case) != 0) {
            return 0;
        }
    }
    return 1;
}

static int str_contain_match(const char *str, const char *sub, int ignore_case) {
    size_t slen = strlen(str);
    size_t sublen = strlen(sub);
    if (slen < sublen) return 0;

    for (size_t i = 0; i <= slen - sublen; i++) {
        int match = 1;
        for (size_t j = 0; j < sublen; j++) {
            if (case_cmp(str[i + j], sub[j], ignore_case) != 0) {
                match = 0;
                break;
            }
        }
        if (match) return 1;
    }
    return 0;
}

static int str_repeated_suffix_match(const char *str, int count) {
    size_t slen = strlen(str);
    if (count <= 1 || slen < (size_t)count) return 0;
    char target = str[slen - 1];
    for (int i = 2; i <= count; i++) {
        if (str[slen - i] != target) {
            return 0;
        }
    }
    return 1;
}

int match_init(match_config_t *cfg) {
    if (cfg->mode == MATCH_REGEX) {
        int cflags = REG_EXTENDED | REG_NOSUB;
        if (cfg->ignore_case) {
            cflags |= REG_ICASE;
        }
        if (regcomp(&cfg->regex_comp, cfg->regex_str, cflags) != 0) {
            cfg->regex_ready = 0;
            return -1;
        }
        cfg->regex_ready = 1;
    }
    return 0;
}

void match_free(match_config_t *cfg) {
    if (cfg->regex_ready) {
        regfree(&cfg->regex_comp);
        cfg->regex_ready = 0;
    }
    if (cfg->file_rules) {
        for (size_t i = 0; i < cfg->file_rule_count; i++) {
            if (cfg->file_rules[i].pattern) {
                free(cfg->file_rules[i].pattern);
            }
        }
        free(cfg->file_rules);
        cfg->file_rules = NULL;
        cfg->file_rule_count = 0;
    }
}

int match_validate_config(match_config_t *cfg, char *err_buf, size_t err_buflen) {
    /* If prefix is specified, ensure it starts with 'T' or 't' */
    if (cfg->mode == MATCH_PREFIX || cfg->mode == MATCH_BOTH) {
        if (strlen(cfg->prefix) == 0) {
            snprintf(err_buf, err_buflen, "前缀不能为空 (Prefix cannot be empty)");
            return -1;
        }
        if (cfg->prefix[0] != 'T' && cfg->prefix[0] != 't') {
            /* Automatically prepend 'T' */
            char temp[64];
            snprintf(temp, sizeof(temp), "T%s", cfg->prefix);
            strncpy(cfg->prefix, temp, sizeof(cfg->prefix) - 1);
            cfg->prefix[sizeof(cfg->prefix) - 1] = '\0';
        }
        if (!is_valid_base58(cfg->prefix)) {
            snprintf(err_buf, err_buflen,
                "前缀包含无效字符！波场 Base58 地址不包含字符 '0', 'O', 'I', 'l'\n"
                "(Prefix contains invalid characters! Base58 excludes '0', 'O', 'I', 'l')");
            return -1;
        }

        /* Tron address prefix constraint: check if prefix falls within [T9yD14..., TZJozA...] */
        static const char b58_order[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
        static const char g_tron_min_addr[] = "T9yD14Nj9j7xAB4dbGeiX9h8unkKDDv9ZR";
        static const char g_tron_max_addr[] = "TZJozAg1ruapycCicgz31GxvYJ1FvTVysk";

        size_t plen = strlen(cfg->prefix);
        char p_max[35], p_min[35];
        for (size_t i = 0; i < plen; i++) {
            p_max[i] = cfg->prefix[i];
            p_min[i] = cfg->prefix[i];
        }
        for (size_t i = plen; i < 34; i++) {
            p_max[i] = 'z';
            p_min[i] = '1';
        }
        p_max[34] = '\0';
        p_min[34] = '\0';

        int cmp_min = 0, cmp_max = 0;
        for (int i = 0; i < 34; i++) {
            int imax = (int)(strchr(b58_order, p_max[i]) - b58_order);
            int itarget_min = (int)(strchr(b58_order, g_tron_min_addr[i]) - b58_order);
            if (cmp_min == 0 && imax != itarget_min) cmp_min = imax - itarget_min;

            int imin = (int)(strchr(b58_order, p_min[i]) - b58_order);
            int itarget_max = (int)(strchr(b58_order, g_tron_max_addr[i]) - b58_order);
            if (cmp_max == 0 && imin != itarget_max) cmp_max = imin - itarget_max;
        }

        if (cmp_min < 0 || cmp_max > 0) {
            snprintf(err_buf, err_buflen,
                "⚠️  波场前缀数学范围提醒:\n"
                "波场主网地址 (0x41前缀) 在 Base58 空间内的有效范围严格在:\n"
                "[%s] 到\n"
                "[%s] 之间。\n"
                "您指定的前缀 '%s' 超出了该数学空间，波场全网绝无可能生成！\n"
                "👉 建议方案: 若想要 888/666/数字连号，请使用【后缀匹配】(如 -s 8888)，\n"
                "   或使用有效前缀 (如 -p TRX / -p VIP / -p ABC)。",
                g_tron_min_addr, g_tron_max_addr, cfg->prefix);
            return -1;
        }

        if (strlen(cfg->prefix) > 10) {
            snprintf(err_buf, err_buflen, "前缀过长（建议 2~7 位）");
            return -1;
        }
    }

    if (cfg->mode == MATCH_SUFFIX || cfg->mode == MATCH_BOTH) {
        if (strlen(cfg->suffix) == 0) {
            snprintf(err_buf, err_buflen, "后缀不能为空 (Suffix cannot be empty)");
            return -1;
        }
        if (!is_valid_base58(cfg->suffix)) {
            snprintf(err_buf, err_buflen,
                "后缀包含无效字符！波场 Base58 地址不包含字符 '0', 'O', 'I', 'l'\n"
                "(Suffix contains invalid characters! Base58 excludes '0', 'O', 'I', 'l')");
            return -1;
        }
        if (strlen(cfg->suffix) > 10) {
            snprintf(err_buf, err_buflen, "后缀过长（建议 3~8 位）");
            return -1;
        }
    }

    if (cfg->mode == MATCH_CONTAIN) {
        if (strlen(cfg->contain) == 0) {
            snprintf(err_buf, err_buflen, "包含内容不能为空");
            return -1;
        }
        if (!is_valid_base58(cfg->contain)) {
            snprintf(err_buf, err_buflen, "包含内容含有非 Base58 字符 ('0', 'O', 'I', 'l')");
            return -1;
        }
    }

    if (cfg->mode == MATCH_REPEATED_SUFFIX) {
        if (cfg->repeat_count < 3 || cfg->repeat_count > 12) {
            snprintf(err_buf, err_buflen, "连号位数需在 3 到 12 位之间");
            return -1;
        }
    }

    if (cfg->mode == MATCH_REGEX) {
        if (strlen(cfg->regex_str) == 0) {
            snprintf(err_buf, err_buflen, "正则表达式不能为空");
            return -1;
        }
    }

    return 0;
}

int match_address(const match_config_t *cfg, const char *address) {
    switch (cfg->mode) {
        case MATCH_PREFIX:
            return str_prefix_match(address, cfg->prefix, cfg->ignore_case);

        case MATCH_SUFFIX:
            return str_suffix_match(address, cfg->suffix, cfg->ignore_case);

        case MATCH_BOTH:
            return str_prefix_match(address, cfg->prefix, cfg->ignore_case) &&
                   str_suffix_match(address, cfg->suffix, cfg->ignore_case);

        case MATCH_CONTAIN:
            return str_contain_match(address, cfg->contain, cfg->ignore_case);

        case MATCH_REPEATED_SUFFIX:
            return str_repeated_suffix_match(address, cfg->repeat_count);

        case MATCH_REGEX:
            if (!cfg->regex_ready) return 0;
            return (regexec(&cfg->regex_comp, address, 0, NULL, 0) == 0);

        case MATCH_FILE:
            for (size_t i = 0; i < cfg->file_rule_count; i++) {
                if (cfg->file_rules[i].is_prefix) {
                    if (str_prefix_match(address, cfg->file_rules[i].pattern, cfg->ignore_case))
                        return 1;
                } else {
                    if (str_suffix_match(address, cfg->file_rules[i].pattern, cfg->ignore_case))
                        return 1;
                }
            }
            return 0;

        default:
            return 0;
    }
}

int match_load_rule_file(match_config_t *cfg, const char *filepath) {
    FILE *fp = fopen(filepath, "r");
    if (!fp) return -1;

    char line[256];
    size_t capacity = 16;
    cfg->file_rules = (file_rule_t *)malloc(capacity * sizeof(file_rule_t));
    cfg->file_rule_count = 0;

    while (fgets(line, sizeof(line), fp)) {
        /* Strip comments and trailing newline */
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '#' || *p == '\n' || *p == '\r' || *p == '\0') continue;

        char *end = p + strlen(p) - 1;
        while (end > p && (*end == '\n' || *end == '\r' || *end == ' ' || *end == '\t')) {
            *end = '\0';
            end--;
        }

        int is_prefix = 0;
        char *pattern = p;
        if (*p == '^') {
            is_prefix = 1;
            pattern++;
        } else if (p[0] == 'T' || p[0] == 't') {
            is_prefix = 1;
        }

        if (!is_valid_base58(pattern)) continue;

        if (cfg->file_rule_count >= capacity) {
            capacity *= 2;
            cfg->file_rules = (file_rule_t *)realloc(cfg->file_rules, capacity * sizeof(file_rule_t));
        }

        cfg->file_rules[cfg->file_rule_count].pattern = strdup(pattern);
        cfg->file_rules[cfg->file_rule_count].is_prefix = is_prefix;
        cfg->file_rule_count++;
    }

    fclose(fp);
    cfg->mode = MATCH_FILE;
    return (int)cfg->file_rule_count;
}
