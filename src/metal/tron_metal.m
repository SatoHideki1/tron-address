#import "tron_metal.h"
#import "../tron.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <signal.h>
#include <openssl/bn.h>
#include <openssl/ec.h>
#include <openssl/obj_mac.h>

#define METAL_DEFAULT_THREADS 32768
#define METAL_STEPS_PER_THREAD 8
#define METAL_TG_SIZE 256

// Metal Shading Language Structs
struct MetalMatchConfig {
    int mode;
    char prefix[35];
    char suffix[35];
    int prefix_len;
    int suffix_len;
    int repeat_count;
    int ignore_case;
};

struct FoundResult {
    uint32_t thread_id;
    uint32_t step_id;
    char address[35];
    uint8_t privkey_hex[65];
};

struct ResultBuffer {
    uint32_t found_count;
    struct FoundResult items[32];
};

struct ThreadSeed {
    uint32_t priv_base[8];
    uint32_t X[8];
    uint32_t Y[8];
    uint32_t Z[8];
};

static volatile sig_atomic_t g_metal_running = 1;

static void metal_sig_handler(int sig) {
    (void)sig;
    g_metal_running = 0;
}

int tron_metal_is_supported(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        return (device != nil);
    }
}

const char *tron_metal_get_device_name(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device) {
            return strdup([[device name] UTF8String]);
        }
        return "Unknown Metal Device";
    }
}

static double get_now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void save_metal_result(const char *address, const char *privkey, const match_config_t *cfg, const char *output_file, double elapsed) {
    time_t now = time(NULL);
    struct tm tm_buf;
    localtime_r(&now, &tm_buf);
    char time_str[64];
    strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", &tm_buf);

    char rule_desc[128];
    switch (cfg->mode) {
        case MATCH_SUFFIX: snprintf(rule_desc, sizeof(rule_desc), "后缀 '%s'", cfg->suffix); break;
        case MATCH_PREFIX: snprintf(rule_desc, sizeof(rule_desc), "前缀 '%s'", cfg->prefix); break;
        case MATCH_BOTH:   snprintf(rule_desc, sizeof(rule_desc), "前缀 '%s' + 后缀 '%s'", cfg->prefix, cfg->suffix); break;
        case MATCH_REPEATED_SUFFIX: snprintf(rule_desc, sizeof(rule_desc), "尾数 %d 连号", cfg->repeat_count); break;
        default: snprintf(rule_desc, sizeof(rule_desc), "自定义规则"); break;
    }

    printf("\n\033[1;32m");
    printf("====================================================================\n");
    printf(" 🎉 恭喜！Metal 3 GPU 硬件加速成功生成匹配的波场靓号！\n");
    printf("--------------------------------------------------------------------\n");
    printf(" 📍 地址 (Address)    : \033[1;33m%s\033[1;32m\n", address);
    printf(" 🔑 私钥 (Private Key): \033[1;37m%s\033[1;32m\n", privkey);
    printf(" 🎯 匹配规则 (Rule)   : %s\n", rule_desc);
    printf(" ⏱️ 累计耗时 (Elapsed) : %.2f 秒\n", elapsed);
    printf(" 💾 结果已保存至      : %s\n", output_file);
    printf("====================================================================\n");
    printf("\033[0m\n");
    fflush(stdout);

    FILE *fp = fopen(output_file, "a");
    if (fp) {
        fprintf(fp, "[%s] Address: %s | PrivateKey: %s | Rule: %s | Elapsed: %.2fs (Metal GPU)\n",
                time_str, address, privkey, rule_desc, elapsed);
        fclose(fp);
    }
}

int tron_metal_start(const match_config_t *cfg,
                     int target_count,
                     const char *output_file,
                     int gpu_limit,
                     int quiet) {
    @autoreleasepool {
        signal(SIGINT, metal_sig_handler);
        signal(SIGTERM, metal_sig_handler);

        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            fprintf(stderr, "错误: 当前 Mac 系统未找到可用的 Metal GPU 设备！\n");
            return -1;
        }

        const char *dev_name = [[device name] UTF8String];

        // Read or load Metal shader source
        NSString *shaderPath = @"src/metal/tron_kernel.metal";
        NSError *readErr = nil;
        NSString *shaderSource = [NSString stringWithContentsOfFile:shaderPath encoding:NSUTF8StringEncoding error:&readErr];
        if (!shaderSource) {
            // Check relative to executable
            NSString *altPath = [[NSBundle mainBundle] pathForResource:@"tron_kernel" ofType:@"metal"];
            if (altPath) {
                shaderSource = [NSString stringWithContentsOfFile:altPath encoding:NSUTF8StringEncoding error:nil];
            }
        }
        if (!shaderSource) {
            fprintf(stderr, "错误: 无法读取 Metal 着色器文件 (%s)！\n", [shaderPath UTF8String]);
            return -1;
        }

        NSError *compileErr = nil;
        id<MTLLibrary> library = [device newLibraryWithSource:shaderSource options:nil error:&compileErr];
        if (!library) {
            fprintf(stderr, "Metal 着色器编译失败: %s\n", [[compileErr localizedDescription] UTF8String]);
            return -1;
        }

        id<MTLFunction> kernelFunc = [library newFunctionWithName:@"tron_search_kernel"];
        if (!kernelFunc) {
            fprintf(stderr, "错误: 着色器中未找到 'tron_search_kernel' 函数！\n");
            return -1;
        }

        id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction:kernelFunc error:&compileErr];
        if (!pso) {
            fprintf(stderr, "创建 Metal Compute 管线失败: %s\n", [[compileErr localizedDescription] UTF8String]);
            return -1;
        }

        id<MTLCommandQueue> queue = [device newCommandQueue];
        if (!queue) {
            fprintf(stderr, "创建 Metal Command Queue 失败！\n");
            return -1;
        }

        uint32_t num_threads = METAL_DEFAULT_THREADS;
        uint32_t steps_per_thread = METAL_STEPS_PER_THREAD;

        // Allocate Shared Buffers
        size_t seeds_size = num_threads * sizeof(struct ThreadSeed);
        id<MTLBuffer> seeds_buf = [device newBufferWithLength:seeds_size options:MTLResourceStorageModeShared];
        id<MTLBuffer> results_buf = [device newBufferWithLength:sizeof(struct ResultBuffer) options:MTLResourceStorageModeShared];
        id<MTLBuffer> cfg_buf = [device newBufferWithLength:sizeof(struct MetalMatchConfig) options:MTLResourceStorageModeShared];
        id<MTLBuffer> steps_buf = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];

        // Fill match config
        struct MetalMatchConfig *mcfg = (struct MetalMatchConfig *)[cfg_buf contents];
        memset(mcfg, 0, sizeof(*mcfg));
        mcfg->ignore_case = cfg->ignore_case;
        mcfg->repeat_count = cfg->repeat_count;

        if (cfg->mode == MATCH_SUFFIX) {
            mcfg->mode = 1;
            strncpy(mcfg->suffix, cfg->suffix, sizeof(mcfg->suffix) - 1);
            mcfg->suffix_len = (int)strlen(cfg->suffix);
        } else if (cfg->mode == MATCH_PREFIX) {
            mcfg->mode = 2;
            strncpy(mcfg->prefix, cfg->prefix, sizeof(mcfg->prefix) - 1);
            mcfg->prefix_len = (int)strlen(cfg->prefix);
        } else if (cfg->mode == MATCH_BOTH) {
            mcfg->mode = 3;
            strncpy(mcfg->prefix, cfg->prefix, sizeof(mcfg->prefix) - 1);
            strncpy(mcfg->suffix, cfg->suffix, sizeof(mcfg->suffix) - 1);
            mcfg->prefix_len = (int)strlen(cfg->prefix);
            mcfg->suffix_len = (int)strlen(cfg->suffix);
        } else if (cfg->mode == MATCH_REPEATED_SUFFIX) {
            mcfg->mode = 4;
        }

        *((uint32_t *)[steps_buf contents]) = steps_per_thread;

        // Precompute initial random seeds on CPU using OpenSSL CSPRNG
        if (!quiet) {
            printf("\033[1;36m===============================================================\n");
            printf("   ⚡ TRON 波场靓号 Metal 3 GPU 硬件加速 (Apple Silicon) ⚡   \n");
            printf("===============================================================\033[0m\n");
            printf("GPU 硬件设备 : \033[1;32m%s\033[0m\n", dev_name);
            printf("GPU 并发线程 : %'u 线程 (%d 步/线程，每批次检索 %'u 地址)\n",
                   num_threads, steps_per_thread, num_threads * steps_per_thread);
            printf("GPU 负载上限 : %d%%\n", gpu_limit);
            printf("正在进行安全 CSPRNG 初始熵播种...\n");
        }

        BN_CTX *bn_ctx = BN_CTX_new();
        EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
        const BIGNUM *order = EC_GROUP_get0_order(group);
        EC_POINT *P = EC_POINT_new(group);
        BIGNUM *k = BN_new();
        BIGNUM *x = BN_new();
        BIGNUM *y = BN_new();

        struct ThreadSeed *seeds = (struct ThreadSeed *)[seeds_buf contents];

        for (uint32_t i = 0; i < num_threads; i++) {
            do {
                BN_priv_rand(k, 256, BN_RAND_TOP_ANY, BN_RAND_BOTTOM_ANY);
            } while (BN_is_zero(k) || BN_cmp(k, order) >= 0);

            EC_POINT_mul(group, P, k, NULL, NULL, bn_ctx);
            EC_POINT_get_affine_coordinates(group, P, x, y, bn_ctx);

            uint8_t buf[32];
            BN_bn2binpad(k, buf, 32);
            for (int w = 0; w < 8; w++) {
                seeds[i].priv_base[w] = ((uint32_t)buf[31 - w*4 - 0]) |
                                        (((uint32_t)buf[31 - w*4 - 1]) << 8) |
                                        (((uint32_t)buf[31 - w*4 - 2]) << 16) |
                                        (((uint32_t)buf[31 - w*4 - 3]) << 24);
            }

            BN_bn2binpad(x, buf, 32);
            for (int w = 0; w < 8; w++) {
                seeds[i].X[w] = ((uint32_t)buf[31 - w*4 - 0]) |
                                (((uint32_t)buf[31 - w*4 - 1]) << 8) |
                                (((uint32_t)buf[31 - w*4 - 2]) << 16) |
                                (((uint32_t)buf[31 - w*4 - 3]) << 24);
            }

            BN_bn2binpad(y, buf, 32);
            for (int w = 0; w < 8; w++) {
                seeds[i].Y[w] = ((uint32_t)buf[31 - w*4 - 0]) |
                                (((uint32_t)buf[31 - w*4 - 1]) << 8) |
                                (((uint32_t)buf[31 - w*4 - 2]) << 16) |
                                (((uint32_t)buf[31 - w*4 - 3]) << 24);
            }

            seeds[i].Z[0] = 1;
            for (int w = 1; w < 8; w++) seeds[i].Z[w] = 0;
        }

        BN_free(x);
        BN_free(y);
        BN_free(k);
        EC_POINT_free(P);
        EC_GROUP_free(group);
        BN_CTX_free(bn_ctx);

        struct ResultBuffer *res = (struct ResultBuffer *)[results_buf contents];
        res->found_count = 0;

        if (!quiet) {
            printf("播种完毕，Metal 硬件流水线已就绪，开始极速算号！\n\n");
        }

        MTLSize gridSize = MTLSizeMake(num_threads, 1, 1);
        MTLSize tgSize = MTLSizeMake(METAL_TG_SIZE, 1, 1);

        uint64_t total_keys = 0;
        int found_total = 0;
        double start_time = get_now_sec();
        double last_report = start_time;
        uint64_t last_keys = 0;

        while (g_metal_running) {
            double batch_start = get_now_sec();

            @autoreleasepool {
                id<MTLCommandBuffer> cmd = [queue commandBuffer];
                id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
                [enc setComputePipelineState:pso];
                [enc setBuffer:seeds_buf offset:0 atIndex:0];
                [enc setBuffer:cfg_buf offset:0 atIndex:1];
                [enc setBuffer:results_buf offset:0 atIndex:2];
                [enc setBuffer:steps_buf offset:0 atIndex:3];

                [enc dispatchThreads:gridSize threadsPerThreadgroup:tgSize];
                [enc endEncoding];
                [cmd commit];
                [cmd waitUntilCompleted];
            }

            uint32_t batch_keys = num_threads * steps_per_thread;
            total_keys += batch_keys;

            // Check if results found
            if (res->found_count > 0) {
                uint32_t count = res->found_count;
                if (count > 32) count = 32;

                for (uint32_t i = 0; i < count; i++) {
                    const char *addr = res->items[i].address;
                    const char *priv = (const char *)res->items[i].privkey_hex;

                    if (tron_verify_keypair(priv, addr)) {
                        found_total++;
                        save_metal_result(addr, priv, cfg, output_file, get_now_sec() - start_time);
                        if (target_count > 0 && found_total >= target_count) {
                            g_metal_running = 0;
                            break;
                        }
                    }
                }
                res->found_count = 0;
            }

            double now = get_now_sec();
            double elapsed = now - start_time;
            double delta_t = now - last_report;

            if (delta_t >= 0.5 && !quiet) {
                double speed = (double)(total_keys - last_keys) / delta_t;
                int hrs = (int)elapsed / 3600;
                int mins = ((int)elapsed % 3600) / 60;
                int secs = (int)elapsed % 60;

                char speed_str[32];
                if (speed >= 1e6) {
                    snprintf(speed_str, sizeof(speed_str), "%.2f MH/s", speed / 1e6);
                } else {
                    snprintf(speed_str, sizeof(speed_str), "%.1f kH/s", speed / 1e3);
                }

                printf("\r\033[K[\033[1;34m耗时: %02d:%02d:%02d\033[0m] "
                       "[\033[1;36m已算: %'lu\033[0m] "
                       "[\033[1;32m速度: %s\033[0m] "
                       "[\033[1;33m命中: %d\033[0m] "
                       "[\033[1;35mGPU: %s\033[0m]",
                       hrs, mins, secs, (unsigned long)total_keys, speed_str, found_total, dev_name);
                fflush(stdout);

                last_report = now;
                last_keys = total_keys;
            }

            // GPU duty cycle throttle
            if (gpu_limit > 0 && gpu_limit < 100) {
                double batch_dur = get_now_sec() - batch_start;
                double target_sleep = batch_dur * (100.0 - gpu_limit) / gpu_limit;
                if (target_sleep > 0.0001) {
                    usleep((useconds_t)(target_sleep * 1e6));
                }
            }
        }

        double total_elapsed = get_now_sec() - start_time;
        printf("\n\n\033[1;36m==================== Metal 运行结束统计 ====================\033[0m\n");
        printf("  - GPU 硬件设备: %s\n", dev_name);
        printf("  - 总共检索地址: %'lu 个\n", (unsigned long)total_keys);
        printf("  - 累计消耗时间: %.2f 秒\n", total_elapsed);
        printf("  - 平均综合算力: %.2f MH/s\n", total_elapsed > 0 ? (total_keys / total_elapsed / 1e6) : 0);
        printf("  - 成功命中靓号: %d 个\n", found_total);
        printf("  - 结果存储文件: %s\n", output_file);
        printf("\033[1;36m============================================================\033[0m\n\n");

        return 0;
    }
}
