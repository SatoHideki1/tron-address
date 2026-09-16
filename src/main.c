#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>
#include <getopt.h>
#include "tron.h"
#include "match.h"
#ifdef __APPLE__
#include "metal/tron_metal.h"
#endif

static volatile sig_atomic_t g_running = 1;
static uint64_t g_total_keys = 0;
static int g_found_count = 0;
static int g_target_count = 1; /* 0 = run indefinitely */
static pthread_mutex_t g_output_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_stats_mutex = PTHREAD_MUTEX_INITIALIZER;
static const char *g_output_file = "found_addresses.txt";
static int g_quiet = 0;
static double g_start_time = 0;

typedef struct {
    int thread_id;
    int cpu_limit; /* 1 - 100 % */
    match_config_t *match_cfg;
    uint64_t local_keys;
} worker_arg_t;

static void sig_handler(int sig) {
    (void)sig;
    g_running = 0;
}

static double get_time_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void print_banner(void) {
    printf("\033[1;36m");
    printf("===============================================================\n");
    printf("     ⚡ TRON 波场地址靓号极速生成器 (Linux / macOS) ⚡    \n");
    printf("     - 安全离线运算 | 点加法加速 | 精确 CPU 占用调控 -        \n");
    printf("===============================================================\n");
    printf("\033[0m");
}

static void print_help(const char *prog) {
    print_banner();
    printf("使用方法 (Usage):\n");
    printf("  %s [选项...]\n\n", prog);
    printf("匹配规则选项 (Matching Options):\n");
    printf("  -s, --suffix <字符串>     匹配地址后缀 (例: -s 88888 或 -s TRX)\n");
    printf("  -p, --prefix <字符串>     匹配地址前缀 (例: -p 888，自动带首字母 T)\n");
    printf("  -b, --both <前缀> <后缀>  同时匹配前缀和后缀 (例: -b 888 888)\n");
    printf("  -m, --contain <字符串>    包含指定字符串 (例: -m VIP)\n");
    printf("  -k, --repeat <位数>       匹配尾部连续相同字符 (例: -k 6 匹配 6连号)\n");
    printf("  -r, --regex <表达式>      POSIX 正则表达式匹配 (例: -r '^T.*8888$')\n");
    printf("  -f, --rule-file <路径>    从文件批量读取匹配规则 (一行一个规则)\n");
    printf("  -i, --ignore-case         忽略大小写匹配 (默认区分大小写)\n\n");
    printf("CPU 与性能调控 (CPU & Performance):\n");
    printf("  -t, --threads <数量>      工作线程数 (默认: 系统全部 CPU 核心)\n");
    printf("  -c, --cpu-limit <1-100>   每个线程 CPU 占用百分比上限 (默认: 100%%)\n");
    printf("                            例: -c 50 占空比限速为 50%%，防止满载\n\n");
    printf("GPU 硬件加速 (Apple Metal):\n");
    printf("  -g, --metal               启用 Metal 3 GPU 硬件加速 (macOS 专属，速度提升 20~60倍)\n\n");
    printf("运行控制 (Run Control):\n");
    printf("  -n, --count <数量>        找到 N 个靓号后自动退出 (默认: 1，设为 0 表示无限寻找)\n");
    printf("  -o, --output <文件路径>   保存结果的文件名 (默认: found_addresses.txt)\n");
    printf("  -q, --quiet               静默模式，仅输出关键信息 (适合后台守护运行)\n");
    printf("  -v, --verify <私钥> <地址> 验证私钥与地址是否相符\n");
    printf("  -h, --help                显示此帮助信息\n\n");
    printf("使用示例 (Examples):\n");
    printf("  1. 寻找以 8888 结尾的靓号，使用 2 核 CPU，占用率限制 60%%:\n");
    printf("     %s -s 8888 -t 2 -c 60\n\n", prog);
    printf("  2. 寻找前缀 T888 且后缀 666 的靓号，单核全速运行:\n");
    printf("     %s -p 888 -s 666 -t 1\n\n", prog);
    printf("  3. 寻找尾部 6 连号 (如 AAAAAA 或 888888):\n");
    printf("     %s -k 6 -c 70\n\n", prog);
}

static void save_found_address(const char *address, const char *privkey_hex, const match_config_t *cfg, double elapsed) {
    pthread_mutex_lock(&g_output_mutex);

    time_t now = time(NULL);
    struct tm tm_buf;
    localtime_r(&now, &tm_buf);
    char time_str[64];
    strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", &tm_buf);

    /* Construct rule description */
    char rule_desc[128];
    switch (cfg->mode) {
        case MATCH_SUFFIX:
            snprintf(rule_desc, sizeof(rule_desc), "后缀 '%s'%s", cfg->suffix, cfg->ignore_case ? " (忽略大小写)" : "");
            break;
        case MATCH_PREFIX:
            snprintf(rule_desc, sizeof(rule_desc), "前缀 '%s'%s", cfg->prefix, cfg->ignore_case ? " (忽略大小写)" : "");
            break;
        case MATCH_BOTH:
            snprintf(rule_desc, sizeof(rule_desc), "前缀 '%s' + 后缀 '%s'%s", cfg->prefix, cfg->suffix, cfg->ignore_case ? " (忽略大小写)" : "");
            break;
        case MATCH_CONTAIN:
            snprintf(rule_desc, sizeof(rule_desc), "包含 '%s'", cfg->contain);
            break;
        case MATCH_REPEATED_SUFFIX:
            snprintf(rule_desc, sizeof(rule_desc), "尾数 %d 连号", cfg->repeat_count);
            break;
        case MATCH_REGEX:
            snprintf(rule_desc, sizeof(rule_desc), "正则 '%s'", cfg->regex_str);
            break;
        case MATCH_FILE:
            snprintf(rule_desc, sizeof(rule_desc), "批量规则文件");
            break;
        default:
            snprintf(rule_desc, sizeof(rule_desc), "自定义规则");
            break;
    }

    /* Print to console */
    printf("\n\033[1;32m");
    printf("====================================================================\n");
    printf(" 🎉 恭喜！成功生成匹配的波场 (TRON) 地址靓号！\n");
    printf("--------------------------------------------------------------------\n");
    printf(" 📍 地址 (Address)    : \033[1;33m%s\033[1;32m\n", address);
    printf(" 🔑 私钥 (Private Key): \033[1;37m%s\033[1;32m\n", privkey_hex);
    printf(" 🎯 匹配规则 (Rule)   : %s\n", rule_desc);
    printf(" ⏱️ 累计耗时 (Elapsed) : %.2f 秒\n", elapsed);
    printf(" 💾 结果已保存至      : %s\n", g_output_file);
    printf("====================================================================\n");
    printf("\033[0m\n");
    fflush(stdout);

    /* Append to file */
    FILE *fp = fopen(g_output_file, "a");
    if (fp) {
        fprintf(fp, "[%s] Address: %s | PrivateKey: %s | Rule: %s | Elapsed: %.2fs\n",
                time_str, address, privkey_hex, rule_desc, elapsed);
        fclose(fp);
    } else {
        fprintf(stderr, "\033[1;31m写入文件 %s 失败！请检查目录写入权限。\033[0m\n", g_output_file);
    }

    pthread_mutex_unlock(&g_output_mutex);
}

static void *worker_thread(void *arg) {
    worker_arg_t *w = (worker_arg_t *)arg;

    tron_context_t ctx;
    if (tron_context_init(&ctx, DEFAULT_RESEED_INTERVAL) != 0) {
        fprintf(stderr, "线程 %d 初始化椭圆曲线环境失败！\n", w->thread_id);
        return NULL;
    }

    tron_keypair_t kp;
    tron_context_reseed(&ctx, &kp);

    /* CPU Duty Cycle Throttling Setup:
     * Window: 20ms = 20,000,000 ns.
     * Work ratio: cpu_limit / 100.0.
     * Check time every 500 keys.
     */
    const int check_interval = 500;
    int counter = 0;
    int throttle_enabled = (w->cpu_limit > 0 && w->cpu_limit < 100);

    const double duty_window = 0.020; /* 20 ms */
    double work_slice = duty_window * ((double)w->cpu_limit / 100.0);
    double sleep_slice = duty_window - work_slice;
    struct timespec sleep_ts;
    sleep_ts.tv_sec = 0;
    sleep_ts.tv_nsec = (long)(sleep_slice * 1e9);

    double window_start = get_time_sec();

    while (g_running) {
        /* Check address */
        if (match_address(w->match_cfg, kp.address)) {
            tron_get_current_keypair(&ctx, &kp);

            pthread_mutex_lock(&g_stats_mutex);
            g_found_count++;
            int cur_found = g_found_count;
            pthread_mutex_unlock(&g_stats_mutex);

            double now = get_time_sec();
            save_found_address(kp.address, kp.privkey_hex, w->match_cfg, now - g_start_time);

            if (g_target_count > 0 && cur_found >= g_target_count) {
                g_running = 0;
                break;
            }
        }

        /* Next key */
        tron_context_next(&ctx, &kp);
        w->local_keys++;
        counter++;

        /* Duty cycle CPU throttle */
        if (throttle_enabled && counter >= check_interval) {
            counter = 0;
            double now = get_time_sec();
            double elapsed_in_window = now - window_start;

            if (elapsed_in_window >= work_slice) {
                nanosleep(&sleep_ts, NULL);
                window_start = get_time_sec();
            }
        }
    }

    tron_context_free(&ctx);
    return NULL;
}

int main(int argc, char *argv[]) {
    signal(SIGINT, sig_handler);
    signal(SIGTERM, sig_handler);

    match_config_t match_cfg;
    memset(&match_cfg, 0, sizeof(match_cfg));
    match_cfg.mode = MATCH_NONE;

    int num_threads = (int)sysconf(_SC_NPROCESSORS_ONLN);
    if (num_threads < 1) num_threads = 1;

    int cpu_limit = 100;
    int opt;

    static struct option long_options[] = {
        {"suffix",      required_argument, 0, 's'},
        {"prefix",      required_argument, 0, 'p'},
        {"both",        required_argument, 0, 'b'},
        {"contain",     required_argument, 0, 'm'},
        {"repeat",      required_argument, 0, 'k'},
        {"regex",       required_argument, 0, 'r'},
        {"rule-file",   required_argument, 0, 'f'},
        {"ignore-case", no_argument,       0, 'i'},
        {"threads",     required_argument, 0, 't'},
        {"cpu-limit",   required_argument, 0, 'c'},
        {"count",       required_argument, 0, 'n'},
        {"output",      required_argument, 0, 'o'},
        {"quiet",       no_argument,       0, 'q'},
        {"verify",      required_argument, 0, 'v'},
        {"metal",       no_argument,       0, 'g'},
        {"gpu",         no_argument,       0, 'g'},
        {"help",        no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };

    int use_metal = 0;

    while ((opt = getopt_long(argc, argv, "s:p:b:m:k:r:f:it:c:n:o:qv:hg", long_options, NULL)) != -1) {
        switch (opt) {
            case 'g':
                use_metal = 1;
                break;
            case 's':
                strncpy(match_cfg.suffix, optarg, sizeof(match_cfg.suffix) - 1);
                if (match_cfg.mode == MATCH_PREFIX) {
                    match_cfg.mode = MATCH_BOTH;
                } else {
                    match_cfg.mode = MATCH_SUFFIX;
                }
                break;
            case 'p':
                strncpy(match_cfg.prefix, optarg, sizeof(match_cfg.prefix) - 1);
                if (match_cfg.mode == MATCH_SUFFIX) {
                    match_cfg.mode = MATCH_BOTH;
                } else {
                    match_cfg.mode = MATCH_PREFIX;
                }
                break;
            case 'b':
                match_cfg.mode = MATCH_BOTH;
                strncpy(match_cfg.prefix, optarg, sizeof(match_cfg.prefix) - 1);
                if (optind < argc && argv[optind][0] != '-') {
                    strncpy(match_cfg.suffix, argv[optind], sizeof(match_cfg.suffix) - 1);
                    optind++;
                }
                break;
            case 'm':
                match_cfg.mode = MATCH_CONTAIN;
                strncpy(match_cfg.contain, optarg, sizeof(match_cfg.contain) - 1);
                break;
            case 'k':
                match_cfg.mode = MATCH_REPEATED_SUFFIX;
                match_cfg.repeat_count = atoi(optarg);
                break;
            case 'r':
                match_cfg.mode = MATCH_REGEX;
                strncpy(match_cfg.regex_str, optarg, sizeof(match_cfg.regex_str) - 1);
                break;
            case 'f':
                if (match_load_rule_file(&match_cfg, optarg) <= 0) {
                    fprintf(stderr, "错误: 无法加载规则文件或文件中无有效 Base58 规则: %s\n", optarg);
                    return 1;
                }
                break;
            case 'i':
                match_cfg.ignore_case = 1;
                break;
            case 't':
                num_threads = atoi(optarg);
                if (num_threads < 1) num_threads = 1;
                break;
            case 'c':
                cpu_limit = atoi(optarg);
                if (cpu_limit < 1) cpu_limit = 1;
                if (cpu_limit > 100) cpu_limit = 100;
                break;
            case 'n':
                g_target_count = atoi(optarg);
                break;
            case 'o':
                g_output_file = optarg;
                break;
            case 'q':
                g_quiet = 1;
                break;
            case 'v':
                if (optind < argc) {
                    const char *priv = optarg;
                    const char *addr = argv[optind];
                    printf("正在验证私钥与地址配对关系...\n");
                    if (tron_verify_keypair(priv, addr)) {
                        printf("\033[1;32m[PASS] 验证成功！私钥与波场地址匹配无误。\033[0m\n");
                        return 0;
                    } else {
                        printf("\033[1;31m[FAIL] 验证失败！该私钥推导出的地址与给定地址不符。\033[0m\n");
                        return 1;
                    }
                } else {
                    fprintf(stderr, "错误: --verify 需要两个参数: <私钥hex> <地址>\n");
                    return 1;
                }
                break;
            case 'h':
            default:
                print_help(argv[0]);
                return 0;
        }
    }

    if (match_cfg.mode == MATCH_NONE) {
        print_help(argv[0]);
        fprintf(stderr, "\n\033[1;31m提示: 请至少指定一种匹配规则 (如 -s 8888 或 -p VIP)！\033[0m\n");
        return 1;
    }

    char err_buf[256] = {0};
    if (match_validate_config(&match_cfg, err_buf, sizeof(err_buf)) != 0) {
        fprintf(stderr, "\n\033[1;31m参数校验失败:\n%s\033[0m\n\n", err_buf);
        return 1;
    }

    if (match_init(&match_cfg) != 0) {
        fprintf(stderr, "\n\033[1;31m初始化匹配引擎失败 (正则表达式可能无效)！\033[0m\n");
        return 1;
    }

    if (!g_quiet) {
        print_banner();
        printf("🔧 工作配置:\n");
        printf("  - 匹配模式: ");
        switch (match_cfg.mode) {
            case MATCH_SUFFIX: printf("后缀匹配 [%s]\n", match_cfg.suffix); break;
            case MATCH_PREFIX: printf("前缀匹配 [%s]\n", match_cfg.prefix); break;
            case MATCH_BOTH:   printf("前缀 [%s] + 后缀 [%s]\n", match_cfg.prefix, match_cfg.suffix); break;
            case MATCH_CONTAIN:printf("包含字符串 [%s]\n", match_cfg.contain); break;
            case MATCH_REPEATED_SUFFIX: printf("尾部 %d 连号\n", match_cfg.repeat_count); break;
            case MATCH_REGEX:  printf("正则表达式 [%s]\n", match_cfg.regex_str); break;
            case MATCH_FILE:   printf("批量文件 (%zu 条规则)\n", match_cfg.file_rule_count); break;
            default: break;
        }
        printf("  - 大小写敏感: %s\n", match_cfg.ignore_case ? "否 (忽略大小写)" : "是 (严格区分)");
        printf("  - 线程数量  : %d 核心\n", num_threads);
        printf("  - CPU 占用率: %d%% 上限\n", cpu_limit);
        printf("  - 目标数量  : %s\n", g_target_count > 0 ? "达到指定数量后停止" : "无限寻找");
        printf("  - 结果文件  : %s\n", g_output_file);
        printf("---------------------------------------------------------------\n");
        printf("🚀 开始计算，按 Ctrl+C 可随时安全终止并保存进度...\n\n");
    }

    if (use_metal) {
#ifdef __APPLE__
        if (tron_metal_is_supported()) {
            return tron_metal_start(&match_cfg, g_target_count, g_output_file, cpu_limit, g_quiet);
        } else {
            fprintf(stderr, "提示: 当前系统未检测到 Metal GPU 支持，将自动回退为 CPU 运算模式。\n");
        }
#else
        fprintf(stderr, "提示: Metal 3 GPU 硬件加速仅在 macOS 系统可用，当前系统将自动使用 CPU 运算模式。\n");
#endif
    }

    pthread_t *threads = (pthread_t *)malloc(num_threads * sizeof(pthread_t));
    worker_arg_t *args = (worker_arg_t *)malloc(num_threads * sizeof(worker_arg_t));

    double start_time = get_time_sec();
    g_start_time = start_time;
    double last_report_time = start_time;
    uint64_t last_total_keys = 0;

    for (int i = 0; i < num_threads; i++) {
        args[i].thread_id = i;
        args[i].cpu_limit = cpu_limit;
        args[i].match_cfg = &match_cfg;
        args[i].local_keys = 0;
        pthread_create(&threads[i], NULL, worker_thread, &args[i]);
    }

    /* Monitoring loop */
    while (g_running) {
        usleep(500000); /* 0.5s refresh */

        uint64_t current_keys = 0;
        for (int i = 0; i < num_threads; i++) {
            current_keys += args[i].local_keys;
        }
        g_total_keys = current_keys;

        double now = get_time_sec();
        double elapsed = now - start_time;
        double delta_t = now - last_report_time;

        if (delta_t >= 0.5 && !g_quiet) {
            double instant_speed = (double)(current_keys - last_total_keys) / delta_t;
            int hrs = (int)elapsed / 3600;
            int mins = ((int)elapsed % 3600) / 60;
            int secs = (int)elapsed % 60;

            /* Format speeds */
            char speed_buf[32];
            if (instant_speed >= 1e6) {
                snprintf(speed_buf, sizeof(speed_buf), "%.2f MH/s", instant_speed / 1e6);
            } else {
                snprintf(speed_buf, sizeof(speed_buf), "%.1f kH/s", instant_speed / 1e3);
            }

            printf("\r\033[K[\033[1;34m耗时: %02d:%02d:%02d\033[0m] "
                   "[\033[1;36m已算: %'lu\033[0m] "
                   "[\033[1;32m速度: %s\033[0m] "
                   "[\033[1;33m命中: %d\033[0m] "
                   "[\033[1;35mCPU: %d%%\033[0m]",
                   hrs, mins, secs, (unsigned long)current_keys, speed_buf, g_found_count, cpu_limit);
            fflush(stdout);

            last_report_time = now;
            last_total_keys = current_keys;
        }
    }

    /* Wait for threads */
    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }

    double total_elapsed = get_time_sec() - start_time;
    uint64_t final_keys = 0;
    for (int i = 0; i < num_threads; i++) {
        final_keys += args[i].local_keys;
    }

    printf("\n\n\033[1;36m==================== 运行结束统计 ====================\033[0m\n");
    printf("  - 总共检索地址: %'lu 个\n", (unsigned long)final_keys);
    printf("  - 累计消耗时间: %.2f 秒\n", total_elapsed);
    printf("  - 平均综合算力: %.1f kH/s\n", total_elapsed > 0 ? (final_keys / total_elapsed / 1e3) : 0);
    printf("  - 成功命中靓号: %d 个\n", g_found_count);
    printf("  - 结果存储文件: %s\n", g_output_file);
    printf("\033[1;36m======================================================\033[0m\n\n");

    free(threads);
    free(args);
    match_free(&match_cfg);

    return 0;
}
