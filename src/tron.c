#include "tron.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Keccak-256 Round Constants */
static const uint64_t keccakf_rndc[24] = {
    0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL,
    0x8000000080008000ULL, 0x000000000000808bULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL, 0x000000000000008aULL,
    0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
    0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL,
    0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
    0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
};

static const int keccakf_rotc[24] = {
    1,  3,  6,  10, 15, 21, 28, 36, 45, 55, 2,  14,
    27, 41, 56, 8,  25, 43, 62, 18, 39, 61, 20, 44
};

static const int keccakf_piln[24] = {
    10, 7,  11, 17, 18, 3,  5,  16, 8,  21, 24, 4,
    15, 23, 19, 13, 12, 2,  20, 14, 22, 9,  6,  1
};

#define ROTL64(x, y) (((x) << (y)) | ((x) >> (64 - (y))))

static void keccakf(uint64_t st[25]) {
    for (int round = 0; round < 24; round++) {
        uint64_t bc[5];
        for (int i = 0; i < 5; i++)
            bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];

        for (int i = 0; i < 5; i++) {
            uint64_t t = bc[(i + 4) % 5] ^ ROTL64(bc[(i + 1) % 5], 1);
            for (int j = 0; j < 25; j += 5)
                st[j + i] ^= t;
        }

        uint64_t t = st[1];
        for (int i = 0; i < 24; i++) {
            int j = keccakf_piln[i];
            bc[0] = st[j];
            st[j] = ROTL64(t, keccakf_rotc[i]);
            t = bc[0];
        }

        for (int j = 0; j < 25; j += 5) {
            for (int i = 0; i < 5; i++)
                bc[i] = st[j + i];
            for (int i = 0; i < 5; i++)
                st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
        }

        st[0] ^= keccakf_rndc[round];
    }
}

/* Optimized Keccak-256 for 64-byte uncompressed public key (X || Y) */
void keccak256_pubkey64(const uint8_t *in64, uint8_t *out32) {
    uint64_t st[25] = {0};
    for (int i = 0; i < 8; i++) {
        st[i] = ((uint64_t)in64[i * 8 + 0])       |
                (((uint64_t)in64[i * 8 + 1]) << 8)  |
                (((uint64_t)in64[i * 8 + 2]) << 16) |
                (((uint64_t)in64[i * 8 + 3]) << 24) |
                (((uint64_t)in64[i * 8 + 4]) << 32) |
                (((uint64_t)in64[i * 8 + 5]) << 40) |
                (((uint64_t)in64[i * 8 + 6]) << 48) |
                (((uint64_t)in64[i * 8 + 7]) << 56);
    }
    /* Keccak padding (pad10*1) for 64 bytes in 136-byte block: byte 64=0x01, byte 135=0x80 */
    st[8] ^= 0x01ULL;
    st[16] ^= 0x8000000000000000ULL;

    keccakf(st);

    for (int i = 0; i < 4; i++) {
        out32[i * 8 + 0] = (uint8_t)(st[i]);
        out32[i * 8 + 1] = (uint8_t)(st[i] >> 8);
        out32[i * 8 + 2] = (uint8_t)(st[i] >> 16);
        out32[i * 8 + 3] = (uint8_t)(st[i] >> 24);
        out32[i * 8 + 4] = (uint8_t)(st[i] >> 32);
        out32[i * 8 + 5] = (uint8_t)(st[i] >> 40);
        out32[i * 8 + 6] = (uint8_t)(st[i] >> 48);
        out32[i * 8 + 7] = (uint8_t)(st[i] >> 56);
    }
}

static const char b58digits[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

int is_valid_base58(const char *str) {
    if (!str || !*str) return 0;
    while (*str) {
        if (!strchr(b58digits, *str)) return 0;
        str++;
    }
    return 1;
}

/* Base58Check encode Tron address from 20-byte Keccak hash (last 20 bytes of Keccak(pubkey)) */
void base58check_tron(const uint8_t *hash20, char *out_addr) {
    uint8_t payload[25];
    payload[0] = 0x41; /* Tron mainnet prefix */
    memcpy(payload + 1, hash20, 20);

    /* Double SHA256 checksum */
    uint8_t s1[SHA256_DIGEST_LENGTH];
    uint8_t s2[SHA256_DIGEST_LENGTH];
    SHA256(payload, 21, s1);
    SHA256(s1, SHA256_DIGEST_LENGTH, s2);
    memcpy(payload + 21, s2, 4);

    /* Base58 encode 25-byte payload */
    uint8_t digits[35] = {0};
    int digitslen = 1;

    for (int i = 0; i < 25; i++) {
        uint32_t carry = payload[i];
        for (int j = 0; j < digitslen; j++) {
            carry += ((uint32_t)digits[j]) << 8;
            digits[j] = (uint8_t)(carry % 58);
            carry /= 58;
        }
        while (carry > 0) {
            digits[digitslen++] = (uint8_t)(carry % 58);
            carry /= 58;
        }
    }

    /* Output 34 characters (Base58 big-endian) */
    for (int i = 0; i < TRON_ADDR_LEN; i++) {
        out_addr[i] = b58digits[digits[TRON_ADDR_LEN - 1 - i]];
    }
    out_addr[TRON_ADDR_LEN] = '\0';
}

int tron_context_init(tron_context_t *ctx, uint64_t reseed_interval) {
    memset(ctx, 0, sizeof(*ctx));
    ctx->bn_ctx = BN_CTX_new();
    if (!ctx->bn_ctx) return -1;

    ctx->group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    if (!ctx->group) {
        BN_CTX_free(ctx->bn_ctx);
        return -1;
    }

    ctx->G = EC_GROUP_get0_generator(ctx->group);
    ctx->order = EC_GROUP_get0_order(ctx->group);

    ctx->P = EC_POINT_new(ctx->group);
    ctx->k = BN_new();
    ctx->x = BN_new();
    ctx->y = BN_new();

    if (!ctx->P || !ctx->k || !ctx->x || !ctx->y) {
        tron_context_free(ctx);
        return -1;
    }

    ctx->steps = 0;
    ctx->reseed_interval = (reseed_interval > 0) ? reseed_interval : DEFAULT_RESEED_INTERVAL;
    return 0;
}

void tron_context_free(tron_context_t *ctx) {
    if (ctx->k) { BN_free(ctx->k); ctx->k = NULL; }
    if (ctx->x) { BN_free(ctx->x); ctx->x = NULL; }
    if (ctx->y) { BN_free(ctx->y); ctx->y = NULL; }
    if (ctx->P) { EC_POINT_free(ctx->P); ctx->P = NULL; }
    if (ctx->group) { EC_GROUP_free(ctx->group); ctx->group = NULL; }
    if (ctx->bn_ctx) { BN_CTX_free(ctx->bn_ctx); ctx->bn_ctx = NULL; }
}

static void derive_address_from_point(tron_context_t *ctx, char *out_addr) {
    uint8_t pub64[64];
    uint8_t keccak_res[32];

    EC_POINT_get_affine_coordinates(ctx->group, ctx->P, ctx->x, ctx->y, ctx->bn_ctx);
    BN_bn2binpad(ctx->x, pub64, 32);
    BN_bn2binpad(ctx->y, pub64 + 32, 32);

    keccak256_pubkey64(pub64, keccak_res);
    base58check_tron(keccak_res + 12, out_addr);
}

int tron_context_reseed(tron_context_t *ctx, tron_keypair_t *kp) {
    /* Generate cryptographically secure random 256-bit scalar k in [1, order-1] */
    do {
        BN_priv_rand(ctx->k, 256, BN_RAND_TOP_ANY, BN_RAND_BOTTOM_ANY);
    } while (BN_is_zero(ctx->k) || BN_cmp(ctx->k, ctx->order) >= 0);

    /* Compute initial public key point: P = k * G */
    EC_POINT_mul(ctx->group, ctx->P, ctx->k, NULL, NULL, ctx->bn_ctx);
    ctx->steps = 0;

    derive_address_from_point(ctx, kp->address);
    return 0;
}

int tron_context_next(tron_context_t *ctx, tron_keypair_t *kp) {
    if (ctx->steps >= ctx->reseed_interval) {
        return tron_context_reseed(ctx, kp);
    }

    /* Point addition: P_next = P + G */
    EC_POINT_add(ctx->group, ctx->P, ctx->P, ctx->G, ctx->bn_ctx);
    ctx->steps++;

    derive_address_from_point(ctx, kp->address);
    return 0;
}

void tron_get_current_keypair(tron_context_t *ctx, tron_keypair_t *kp) {
    /* Calculate actual private key: k_actual = (k_base + steps) mod order */
    BIGNUM *k_actual = BN_new();
    BIGNUM *bn_steps = BN_new();

    BN_set_word(bn_steps, ctx->steps);
    BN_mod_add(k_actual, ctx->k, bn_steps, ctx->order, ctx->bn_ctx);

    BN_bn2binpad(k_actual, kp->privkey_bytes, 32);

    /* Format 64-char lowercase hex */
    const char hex_chars[] = "0123456789abcdef";
    for (int i = 0; i < 32; i++) {
        kp->privkey_hex[i * 2 + 0] = hex_chars[kp->privkey_bytes[i] >> 4];
        kp->privkey_hex[i * 2 + 1] = hex_chars[kp->privkey_bytes[i] & 0x0f];
    }
    kp->privkey_hex[64] = '\0';

    BN_free(k_actual);
    BN_free(bn_steps);
}

int tron_verify_keypair(const char *priv_hex, const char *expected_addr) {
    if (!priv_hex || strlen(priv_hex) != 64) return 0;

    BN_CTX *bn_ctx = BN_CTX_new();
    EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);
    BIGNUM *k = BN_new();
    EC_POINT *P = EC_POINT_new(group);
    BIGNUM *x = BN_new();
    BIGNUM *y = BN_new();

    BN_hex2bn(&k, priv_hex);
    EC_POINT_mul(group, P, k, NULL, NULL, bn_ctx);

    uint8_t pub64[64];
    uint8_t keccak_res[32];
    char calc_addr[35];

    EC_POINT_get_affine_coordinates(group, P, x, y, bn_ctx);
    BN_bn2binpad(x, pub64, 32);
    BN_bn2binpad(y, pub64 + 32, 32);

    keccak256_pubkey64(pub64, keccak_res);
    base58check_tron(keccak_res + 12, calc_addr);

    int ok = (strcmp(calc_addr, expected_addr) == 0);

    BN_free(x);
    BN_free(y);
    EC_POINT_free(P);
    BN_free(k);
    EC_GROUP_free(group);
    BN_CTX_free(bn_ctx);

    return ok;
}
