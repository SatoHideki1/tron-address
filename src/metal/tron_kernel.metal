#include <metal_stdlib>
using namespace metal;

// ─── secp256k1 Curve Constants ──────────────────────────────────────────────
constant uint32_t P_MOD[8] = {
    0xFFFFFC2F, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF,
    0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF
};

constant uint32_t G_X[8] = {
    0x16F81798, 0x59F2815B, 0x2DCE28D9, 0x029BFCDB,
    0xCE870B07, 0x55A06295, 0xF9DCBBAC, 0x79BE667E
};

constant uint32_t G_Y[8] = {
    0xFB10D4B8, 0x9C47D08F, 0xA6855419, 0xFD17B448,
    0x0E1108A8, 0x5DA4FBFC, 0x26A3C465, 0x483ADA77
};

constant uint32_t CURVE_ORDER[8] = {
    0xD0364141, 0xBFD25E8C, 0xAF48A03B, 0xBAAEDCE6,
    0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF
};

constant uint32_t P_MINUS_2[8] = {
    0xFFFFFC2D, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF,
    0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF
};

constant char HEX_CHARS[17] = "0123456789abcdef";

// ─── Big Integer Modulo Arithmetic ──────────────────────────────────────────
inline void mod_add(thread uint32_t r[8], thread const uint32_t a[8], thread const uint32_t b[8]) {
    uint64_t c = 0;
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        c += (uint64_t)a[i] + b[i];
        r[i] = (uint32_t)c;
        c >>= 32;
    }
    uint64_t borrow = 0;
    uint32_t tmp[8];
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        uint64_t diff = (uint64_t)r[i] - P_MOD[i] - borrow;
        tmp[i] = (uint32_t)diff;
        borrow = (diff >> 63) & 1;
    }
    if (c || borrow == 0) {
        #pragma unroll
        for (int i = 0; i < 8; i++) r[i] = tmp[i];
    }
}

inline void mod_sub(thread uint32_t r[8], thread const uint32_t a[8], thread const uint32_t b[8]) {
    uint64_t borrow = 0;
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        uint64_t diff = (uint64_t)a[i] - b[i] - borrow;
        r[i] = (uint32_t)diff;
        borrow = (diff >> 63) & 1;
    }
    if (borrow) {
        uint64_t c = 0;
        #pragma unroll
        for (int i = 0; i < 8; i++) {
            c += (uint64_t)r[i] + P_MOD[i];
            r[i] = (uint32_t)c;
            c >>= 32;
        }
    }
}

inline void mul256(thread uint32_t res[16], thread const uint32_t a[8], thread const uint32_t b[8]) {
    uint64_t r[16] = {0};
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        uint64_t carry = 0;
        #pragma unroll
        for (int j = 0; j < 8; j++) {
            uint64_t prod = (uint64_t)a[i] * b[j] + r[i + j] + carry;
            r[i + j] = prod & 0xFFFFFFFFULL;
            carry = prod >> 32;
        }
        r[i + 8] += carry;
    }
    #pragma unroll
    for (int i = 0; i < 16; i++) res[i] = (uint32_t)r[i];
}

inline void reduce512(thread uint32_t r[8], thread const uint32_t w[16]) {
    uint32_t low[8];
    #pragma unroll
    for (int i = 0; i < 8; i++) low[i] = w[i];

    uint64_t c = 0;
    uint32_t t1[9];
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        uint64_t prod = (uint64_t)w[8 + i] * 977 + c;
        t1[i] = (uint32_t)prod;
        c = prod >> 32;
    }
    t1[8] = (uint32_t)c;

    uint32_t t2[9];
    t2[0] = 0;
    #pragma unroll
    for (int i = 0; i < 8; i++) t2[i + 1] = w[8 + i];

    c = 0;
    uint32_t s[9];
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        c += (uint64_t)low[i] + t1[i];
        s[i] = (uint32_t)c;
        c >>= 32;
    }
    s[8] = (uint32_t)(c + t1[8]);

    c = 0;
    #pragma unroll
    for (int i = 0; i < 9; i++) {
        c += (uint64_t)s[i] + t2[i];
        s[i] = (uint32_t)c;
        c >>= 32;
    }

    uint64_t top = ((uint64_t)c << 32) | s[8];
    uint64_t fold1 = top * 977;
    c = (uint64_t)s[0] + (fold1 & 0xFFFFFFFFULL);
    r[0] = (uint32_t)c; c >>= 32;
    c += (uint64_t)s[1] + (fold1 >> 32) + (top & 0xFFFFFFFFULL);
    r[1] = (uint32_t)c; c >>= 32;
    c += (uint64_t)s[2] + (top >> 32);
    r[2] = (uint32_t)c; c >>= 32;
    #pragma unroll
    for (int i = 3; i < 8; i++) {
        c += (uint64_t)s[i];
        r[i] = (uint32_t)c;
        c >>= 32;
    }
    if (c) {
        uint64_t fold2 = c * 977;
        c = (uint64_t)r[0] + (fold2 & 0xFFFFFFFFULL);
        r[0] = (uint32_t)c; c >>= 32;
        c += (uint64_t)r[1] + (fold2 >> 32);
        r[1] = (uint32_t)c; c >>= 32;
        #pragma unroll
        for (int i = 2; i < 8; i++) {
            c += (uint64_t)r[i];
            r[i] = (uint32_t)c;
            c >>= 32;
        }
    }
    uint64_t borrow = 0;
    uint32_t tmp[8];
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        uint64_t diff = (uint64_t)r[i] - P_MOD[i] - borrow;
        tmp[i] = (uint32_t)diff;
        borrow = (diff >> 63) & 1;
    }
    if (borrow == 0) {
        #pragma unroll
        for (int i = 0; i < 8; i++) r[i] = tmp[i];
    }
}

inline void mod_mul(thread uint32_t r[8], thread const uint32_t a[8], thread const uint32_t b[8]) {
    uint32_t w[16];
    mul256(w, a, b);
    reduce512(r, w);
}

inline void mod_inv(thread uint32_t r[8], thread const uint32_t a[8]) {
    uint32_t res[8] = {1, 0, 0, 0, 0, 0, 0, 0};
    uint32_t base[8];
    #pragma unroll
    for (int i = 0; i < 8; i++) base[i] = a[i];

    for (int i = 0; i < 8; i++) {
        uint32_t word = P_MINUS_2[i];
        for (int b = 0; b < 32; b++) {
            if ((word >> b) & 1) {
                mod_mul(res, res, base);
            }
            mod_mul(base, base, base);
        }
    }
    #pragma unroll
    for (int i = 0; i < 8; i++) r[i] = res[i];
}

// ─── Jacobian Mixed Point Addition: P3 = P1(Jacobian) + P2(Affine) ─────────
inline void point_add_mixed(thread uint32_t X3[8], thread uint32_t Y3[8], thread uint32_t Z3[8],
                            thread const uint32_t X1[8], thread const uint32_t Y1[8], thread const uint32_t Z1[8],
                            constant uint32_t x2[8], constant uint32_t y2[8]) {
    uint32_t Z1_2[8], Z1_3[8], U2[8], S2[8], H[8], R[8], H2[8], H3[8], U1H2[8], t[8];
    mod_mul(Z1_2, Z1, Z1);
    mod_mul(Z1_3, Z1_2, Z1);

    uint32_t tx2[8], ty2[8];
    #pragma unroll
    for (int i = 0; i < 8; i++) { tx2[i] = x2[i]; ty2[i] = y2[i]; }

    mod_mul(U2, tx2, Z1_2);
    mod_mul(S2, ty2, Z1_3);

    mod_sub(H, U2, X1);
    mod_sub(R, S2, Y1);

    mod_mul(H2, H, H);
    mod_mul(H3, H2, H);
    mod_mul(U1H2, X1, H2);

    mod_mul(X3, R, R);
    mod_sub(X3, X3, H3);
    mod_sub(X3, X3, U1H2);
    mod_sub(X3, X3, U1H2);

    mod_sub(t, U1H2, X3);
    mod_mul(Y3, R, t);
    mod_mul(t, Y1, H3);
    mod_sub(Y3, Y3, t);

    mod_mul(Z3, H, Z1);
}

// ─── Keccak-256 for 64-byte uncompressed public key (X || Y) ────────────────
constant uint64_t KECCAK_RC[24] = {
    0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL,
    0x8000000080008000ULL, 0x000000000000808bULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL, 0x000000000000008aULL,
    0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
    0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL,
    0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
    0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
};

constant int KECCAK_ROTC[24] = {
    1,  3,  6,  10, 15, 21, 28, 36, 45, 55, 2,  14,
    27, 41, 56, 8,  25, 43, 62, 18, 39, 61, 20, 44
};

constant int KECCAK_PILN[24] = {
    10, 7,  11, 17, 18, 3,  5,  16, 8,  21, 24, 4,
    15, 23, 19, 13, 12, 2,  20, 14, 22, 9,  6,  1
};

#define ROTL64(x, y) (((x) << (y)) | ((x) >> (64 - (y))))

inline void keccak_f1600(thread uint64_t st[25]) {
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
            int j = KECCAK_PILN[i];
            bc[0] = st[j];
            st[j] = ROTL64(t, KECCAK_ROTC[i]);
            t = bc[0];
        }

        for (int j = 0; j < 25; j += 5) {
            for (int i = 0; i < 5; i++)
                bc[i] = st[j + i];
            for (int i = 0; i < 5; i++)
                st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
        }

        st[0] ^= KECCAK_RC[round];
    }
}

inline void keccak256_pubkey(thread const uint8_t in64[64], thread uint8_t out32[32]) {
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
    st[8] ^= 0x01ULL;
    st[16] ^= 0x8000000000000000ULL;

    keccak_f1600(st);

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

// ─── Hardware SHA-256 for Checksum ──────────────────────────────────────────
constant uint32_t SHA256_K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

#define ROTR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
#define CH(x, y, z) (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define SIG0(x) (ROTR(x, 2) ^ ROTR(x, 13) ^ ROTR(x, 22))
#define SIG1(x) (ROTR(x, 6) ^ ROTR(x, 11) ^ ROTR(x, 25))
#define OM0(x) (ROTR(x, 7) ^ ROTR(x, 18) ^ ((x) >> 3))
#define OM1(x) (ROTR(x, 17) ^ ROTR(x, 19) ^ ((x) >> 10))

inline void sha256_transform(thread uint32_t state[8], thread const uint32_t block[16]) {
    uint32_t w[64];
    for (int i = 0; i < 16; i++) w[i] = block[i];
    for (int i = 16; i < 64; i++) w[i] = OM1(w[i - 2]) + w[i - 7] + OM0(w[i - 15]) + w[i - 16];

    uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint32_t e = state[4], f = state[5], g = state[6], h = state[7];

    for (int i = 0; i < 64; i++) {
        uint32_t t1 = h + SIG1(e) + CH(e, f, g) + SHA256_K[i] + w[i];
        uint32_t t2 = SIG0(a) + MAJ(a, b, c);
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }

    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

// Compute Double SHA256 for 21-byte Tron payload (0x41 + 20-byte hash)
inline uint32_t double_sha256(thread const uint8_t in21[21]) {
    // Pass 1: 21 bytes -> pad to 64 bytes (1 block)
    uint32_t b1[16] = {0};
    // Pack 21 bytes (big-endian 32-bit words)
    b1[0] = ((uint32_t)in21[0] << 24) | ((uint32_t)in21[1] << 16) | ((uint32_t)in21[2] << 8) | in21[3];
    b1[1] = ((uint32_t)in21[4] << 24) | ((uint32_t)in21[5] << 16) | ((uint32_t)in21[6] << 8) | in21[7];
    b1[2] = ((uint32_t)in21[8] << 24) | ((uint32_t)in21[9] << 16) | ((uint32_t)in21[10] << 8) | in21[11];
    b1[3] = ((uint32_t)in21[12] << 24) | ((uint32_t)in21[13] << 16) | ((uint32_t)in21[14] << 8) | in21[15];
    b1[4] = ((uint32_t)in21[16] << 24) | ((uint32_t)in21[17] << 16) | ((uint32_t)in21[18] << 8) | in21[19];
    b1[5] = ((uint32_t)in21[20] << 24) | 0x00800000; // byte 21=0x80 pad
    b1[15] = 21 * 8; // length in bits = 168

    uint32_t s1[8] = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    };
    sha256_transform(s1, b1);

    // Pass 2: 32 bytes -> pad to 64 bytes (1 block)
    uint32_t b2[16] = {0};
    for (int i = 0; i < 8; i++) b2[i] = s1[i];
    b2[8] = 0x80000000;
    b2[15] = 256; // length in bits = 256

    uint32_t s2[8] = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    };
    sha256_transform(s2, b2);

    return s2[0];
}

// ─── Base58Check Encoding (25 bytes payload -> 34 char Tron address) ────────
constant char BASE58_CHARS[59] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

inline void base58check_encode(thread const uint8_t payload[25], thread char out34[35]) {
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

    for (int i = 0; i < 34; i++) {
        out34[i] = BASE58_CHARS[digits[33 - i]];
    }
    out34[34] = '\0';
}

// ─── Match Configuration & Results ──────────────────────────────────────────
enum MetalMatchMode {
    METAL_MATCH_SUFFIX = 1,
    METAL_MATCH_PREFIX = 2,
    METAL_MATCH_BOTH   = 3,
    METAL_MATCH_REPEAT = 4
};

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
    atomic_uint found_count;
    FoundResult items[32];
};

struct ThreadSeed {
    uint32_t priv_base[8]; // Thread base private key
    uint32_t X[8];
    uint32_t Y[8];
    uint32_t Z[8];
};

inline char to_lower_c(char c) {
    if (c >= 'A' && c <= 'Z') return c + 32;
    return c;
}

inline bool check_pattern_match(thread const char addr[35], constant MetalMatchConfig &cfg) {
    if (cfg.mode == METAL_MATCH_SUFFIX) {
        int start = 34 - cfg.suffix_len;
        for (int i = 0; i < cfg.suffix_len; i++) {
            char a = addr[start + i];
            char b = cfg.suffix[i];
            if (cfg.ignore_case) { a = to_lower_c(a); b = to_lower_c(b); }
            if (a != b) return false;
        }
        return true;
    }
    else if (cfg.mode == METAL_MATCH_PREFIX) {
        for (int i = 0; i < cfg.prefix_len; i++) {
            char a = addr[i];
            char b = cfg.prefix[i];
            if (cfg.ignore_case) { a = to_lower_c(a); b = to_lower_c(b); }
            if (a != b) return false;
        }
        return true;
    }
    else if (cfg.mode == METAL_MATCH_BOTH) {
        // Check prefix
        for (int i = 0; i < cfg.prefix_len; i++) {
            char a = addr[i];
            char b = cfg.prefix[i];
            if (cfg.ignore_case) { a = to_lower_c(a); b = to_lower_c(b); }
            if (a != b) return false;
        }
        // Check suffix
        int start = 34 - cfg.suffix_len;
        for (int i = 0; i < cfg.suffix_len; i++) {
            char a = addr[start + i];
            char b = cfg.suffix[i];
            if (cfg.ignore_case) { a = to_lower_c(a); b = to_lower_c(b); }
            if (a != b) return false;
        }
        return true;
    }
    else if (cfg.mode == METAL_MATCH_REPEAT) {
        char last = addr[33];
        for (int i = 1; i < cfg.repeat_count; i++) {
            if (addr[33 - i] != last) return false;
        }
        return true;
    }
    return false;
}

// Format 32-byte big-endian private key into hex
inline void privkey_to_hex(thread const uint32_t k[8], thread char hex[65]) {
    for (int i = 0; i < 8; i++) {
        uint32_t w = k[7 - i]; // Big-endian word order
        hex[i * 8 + 0] = HEX_CHARS[(w >> 28) & 0xF];
        hex[i * 8 + 1] = HEX_CHARS[(w >> 24) & 0xF];
        hex[i * 8 + 2] = HEX_CHARS[(w >> 20) & 0xF];
        hex[i * 8 + 3] = HEX_CHARS[(w >> 16) & 0xF];
        hex[i * 8 + 4] = HEX_CHARS[(w >> 12) & 0xF];
        hex[i * 8 + 5] = HEX_CHARS[(w >> 8) & 0xF];
        hex[i * 8 + 6] = HEX_CHARS[(w >> 4) & 0xF];
        hex[i * 8 + 7] = HEX_CHARS[w & 0xF];
    }
    hex[64] = '\0';
}

// ─── Main Metal Compute Kernel ──────────────────────────────────────────────
kernel void tron_search_kernel(device ThreadSeed *seeds            [[buffer(0)]],
                              constant MetalMatchConfig &cfg      [[buffer(1)]],
                              device ResultBuffer *results        [[buffer(2)]],
                              constant uint32_t &steps_per_thread [[buffer(3)]],
                              uint id                             [[thread_position_in_grid]]) {
    uint32_t X[8], Y[8], Z[8], priv_cur[8];
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        X[i] = seeds[id].X[i];
        Y[i] = seeds[id].Y[i];
        Z[i] = seeds[id].Z[i];
        priv_cur[i] = seeds[id].priv_base[i];
    }

    for (uint32_t step = 0; step < steps_per_thread; step++) {
        // Point addition: P = P + G
        uint32_t X_next[8], Y_next[8], Z_next[8];
        point_add_mixed(X_next, Y_next, Z_next, X, Y, Z, G_X, G_Y);
        #pragma unroll
        for (int i = 0; i < 8; i++) {
            X[i] = X_next[i]; Y[i] = Y_next[i]; Z[i] = Z_next[i];
        }

        // Private key increment mod CURVE_ORDER
        uint64_t carry = 1;
        #pragma unroll
        for (int i = 0; i < 8; i++) {
            carry += (uint64_t)priv_cur[i];
            priv_cur[i] = (uint32_t)carry;
            carry >>= 32;
        }

        // Convert Jacobian (X, Y, Z) to Affine (x, y)
        uint32_t Z_inv[8], Z_inv2[8], Z_inv3[8], aff_x[8], aff_y[8];
        mod_inv(Z_inv, Z);
        mod_mul(Z_inv2, Z_inv, Z_inv);
        mod_mul(Z_inv3, Z_inv2, Z_inv);
        mod_mul(aff_x, X, Z_inv2);
        mod_mul(aff_y, Y, Z_inv3);

        // Pack (aff_x, aff_y) into 64-byte big-endian uncompressed pubkey
        uint8_t pub64[64];
        for (int i = 0; i < 8; i++) {
            uint32_t wx = aff_x[7 - i];
            pub64[i * 4 + 0] = (uint8_t)(wx >> 24);
            pub64[i * 4 + 1] = (uint8_t)(wx >> 16);
            pub64[i * 4 + 2] = (uint8_t)(wx >> 8);
            pub64[i * 4 + 3] = (uint8_t)(wx);

            uint32_t wy = aff_y[7 - i];
            pub64[32 + i * 4 + 0] = (uint8_t)(wy >> 24);
            pub64[32 + i * 4 + 1] = (uint8_t)(wy >> 16);
            pub64[32 + i * 4 + 2] = (uint8_t)(wy >> 8);
            pub64[32 + i * 4 + 3] = (uint8_t)(wy);
        }

        // Keccak-256
        uint8_t keccak_hash[32];
        keccak256_pubkey(pub64, keccak_hash);

        // 21-byte Tron payload: 0x41 + keccak[12..31]
        uint8_t payload[25];
        payload[0] = 0x41;
        for (int i = 0; i < 20; i++) payload[1 + i] = keccak_hash[12 + i];

        // Double SHA256 checksum
        uint32_t cs = double_sha256(payload);
        payload[21] = (uint8_t)(cs >> 24);
        payload[22] = (uint8_t)(cs >> 16);
        payload[23] = (uint8_t)(cs >> 8);
        payload[24] = (uint8_t)(cs);

        // Base58Check
        char address[35];
        base58check_encode(payload, address);

        // Test rule match
        if (check_pattern_match(address, cfg)) {
            uint slot = atomic_fetch_add_explicit(&results->found_count, 1, memory_order_relaxed);
            if (slot < 32) {
                results->items[slot].thread_id = id;
                results->items[slot].step_id = step;
                for (int i = 0; i < 35; i++) results->items[slot].address[i] = address[i];
                char hex[65];
                privkey_to_hex(priv_cur, hex);
                for (int i = 0; i < 65; i++) results->items[slot].privkey_hex[i] = (uint8_t)hex[i];
            }
        }
    }

    // Save state back
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        seeds[id].X[i] = X[i];
        seeds[id].Y[i] = Y[i];
        seeds[id].Z[i] = Z[i];
        seeds[id].priv_base[i] = priv_cur[i];
    }
}
