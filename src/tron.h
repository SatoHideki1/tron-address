#ifndef TRON_H
#define TRON_H

#include <stdint.h>
#include <stddef.h>
#include <openssl/ec.h>
#include <openssl/bn.h>
#include <openssl/obj_mac.h>
#include <openssl/sha.h>

#ifdef __cplusplus
extern "C" {
#endif

#define TRON_ADDR_LEN 34
#define TRON_PRIV_HEX_LEN 64
#define DEFAULT_RESEED_INTERVAL 1000000ULL

typedef struct {
    uint8_t privkey_bytes[32];
    char privkey_hex[TRON_PRIV_HEX_LEN + 1];
    char address[TRON_ADDR_LEN + 1];
} tron_keypair_t;

typedef struct {
    BN_CTX *bn_ctx;
    EC_GROUP *group;
    const EC_POINT *G;
    const BIGNUM *order;
    EC_POINT *P;
    BIGNUM *k;
    BIGNUM *x;
    BIGNUM *y;
    uint64_t steps;
    uint64_t reseed_interval;
} tron_context_t;

/* Initialize / free thread-local Tron context */
int tron_context_init(tron_context_t *ctx, uint64_t reseed_interval);
void tron_context_free(tron_context_t *ctx);

/* Reseed context with a cryptographically secure random private key */
int tron_context_reseed(tron_context_t *ctx, tron_keypair_t *kp);

/* Advance to next key using Point Addition: P_next = P + G, k_next = (k + 1) mod order */
int tron_context_next(tron_context_t *ctx, tron_keypair_t *kp);

/* Recover and format the final private key into hex for the current step */
void tron_get_current_keypair(tron_context_t *ctx, tron_keypair_t *kp);

/* Standalone verification: verify that a private key produces the given address */
int tron_verify_keypair(const char *priv_hex, const char *expected_addr);

/* Keccak-256 hash for 64-byte uncompressed public key */
void keccak256_pubkey64(const uint8_t *in64, uint8_t *out32);

/* Base58Check encode Tron address from 20-byte Keccak hash */
void base58check_tron(const uint8_t *hash20, char *out_addr);

/* Check if a string consists only of valid Base58 characters */
int is_valid_base58(const char *str);

#ifdef __cplusplus
}
#endif

#endif /* TRON_H */
