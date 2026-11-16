#include "atr_chacha20_poly1305.h"
#include "tweetnacl.h"
#include <string.h>
#include <stdlib.h>

#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__)
#include <stdlib.h>
void randombytes(unsigned char *ptr, unsigned long long length) {
    arc4random_buf(ptr, (size_t)length);
}
#else
void randombytes(unsigned char *ptr, unsigned long long length) {
    for (unsigned long long i = 0; i < length; i++) {
        ptr[i] = (unsigned char)rand();
    }
}
#endif

static inline uint32_t rotl32(uint32_t x, int n) {
    return (x << n) | (x >> (32 - n));
}

static inline uint32_t load32_le(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static inline void store32_le(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xff);
    p[1] = (uint8_t)((v >> 8) & 0xff);
    p[2] = (uint8_t)((v >> 16) & 0xff);
    p[3] = (uint8_t)((v >> 24) & 0xff);
}

static inline void store64_le(uint8_t *p, uint64_t v) {
    store32_le(p, (uint32_t)(v & 0xffffffff));
    store32_le(p + 4, (uint32_t)(v >> 32));
}

#define QR(a, b, c, d) \
    a += b; d ^= a; d = rotl32(d, 16); \
    c += d; b ^= c; b = rotl32(b, 12); \
    a += b; d ^= a; d = rotl32(d, 8);  \
    c += d; b ^= c; b = rotl32(b, 7);

static void chacha20_block(uint32_t out[16], const uint32_t in[16]) {
    uint32_t x[16];
    for (int i = 0; i < 16; i++) x[i] = in[i];
    
    for (int i = 0; i < 10; i++) {
        // Column round
        QR(x[0], x[4], x[8],  x[12]);
        QR(x[1], x[5], x[9],  x[13]);
        QR(x[2], x[6], x[10], x[14]);
        QR(x[3], x[7], x[11], x[15]);
        // Diagonal round
        QR(x[0], x[5], x[10], x[15]);
        QR(x[1], x[6], x[11], x[12]);
        QR(x[2], x[7], x[8],  x[13]);
        QR(x[3], x[4], x[9],  x[14]);
    }
    
    for (int i = 0; i < 16; i++) out[i] = x[i] + in[i];
}

static void chacha20_xor(const uint8_t key[32], uint32_t counter, const uint8_t nonce[12], const uint8_t *in, size_t len, uint8_t *out) {
    uint32_t state[16];
    state[0] = 0x61707865;
    state[1] = 0x3320646e;
    state[2] = 0x79622d32;
    state[3] = 0x6b206574;
    
    for (int i = 0; i < 8; i++) {
        state[4 + i] = load32_le(key + i * 4);
    }
    state[12] = counter;
    state[13] = load32_le(nonce);
    state[14] = load32_le(nonce + 4);
    state[15] = load32_le(nonce + 8);
    
    uint32_t block[16];
    uint8_t block_bytes[64];
    
    while (len > 0) {
        chacha20_block(block, state);
        state[12]++;
        for (int i = 0; i < 16; i++) {
            store32_le(block_bytes + i * 4, block[i]);
        }
        
        size_t n = len < 64 ? len : 64;
        for (size_t i = 0; i < n; i++) {
            out[i] = in[i] ^ block_bytes[i];
        }
        in += n;
        out += n;
        len -= n;
    }
}

// -----------------------------------------------------------------------------
// ChaCha20-Poly1305 AEAD (RFC 8439)
// -----------------------------------------------------------------------------
int atr_chacha20_poly1305_encrypt(
    const uint8_t key[32],
    const uint8_t nonce[12],
    const uint8_t *aad, size_t aad_len,
    const uint8_t *plaintext, size_t plaintext_len,
    uint8_t *ciphertext,
    uint8_t tag[16]
) {
    // 1. Generate one-time Poly1305 key with counter = 0
    uint8_t otk[64];
    memset(otk, 0, sizeof(otk));
    chacha20_xor(key, 0, nonce, otk, 64, otk);
    
    // 2. Encrypt plaintext with counter = 1
    if (plaintext_len > 0 && plaintext && ciphertext) {
        chacha20_xor(key, 1, nonce, plaintext, plaintext_len, ciphertext);
    }
    
    // 3. Construct Poly1305 buffer:
    // aad || pad(aad) || ciphertext || pad(ciphertext) || len(aad) || len(ciphertext)
    size_t aad_pad = (aad_len % 16 == 0) ? 0 : (16 - (aad_len % 16));
    size_t ct_pad = (plaintext_len % 16 == 0) ? 0 : (16 - (plaintext_len % 16));
    size_t poly_len = aad_len + aad_pad + plaintext_len + ct_pad + 16;
    
    uint8_t *poly_buf = (uint8_t *)calloc(1, poly_len);
    if (!poly_buf) return -1;
    
    size_t offset = 0;
    if (aad && aad_len > 0) {
        memcpy(poly_buf + offset, aad, aad_len);
    }
    offset += aad_len + aad_pad;
    
    if (ciphertext && plaintext_len > 0) {
        memcpy(poly_buf + offset, ciphertext, plaintext_len);
    }
    offset += plaintext_len + ct_pad;
    
    store64_le(poly_buf + offset, (uint64_t)aad_len);
    offset += 8;
    store64_le(poly_buf + offset, (uint64_t)plaintext_len);
    offset += 8;
    
    crypto_onetimeauth(tag, poly_buf, poly_len, otk);
    free(poly_buf);
    
    return 0;
}

int atr_chacha20_poly1305_decrypt(
    const uint8_t key[32],
    const uint8_t nonce[12],
    const uint8_t *aad, size_t aad_len,
    const uint8_t *ciphertext, size_t ciphertext_len,
    const uint8_t tag[16],
    uint8_t *plaintext
) {
    // 1. Generate one-time Poly1305 key with counter = 0
    uint8_t otk[64];
    memset(otk, 0, sizeof(otk));
    chacha20_xor(key, 0, nonce, otk, 64, otk);
    
    // 2. Verify MAC tag first
    size_t aad_pad = (aad_len % 16 == 0) ? 0 : (16 - (aad_len % 16));
    size_t ct_pad = (ciphertext_len % 16 == 0) ? 0 : (16 - (ciphertext_len % 16));
    size_t poly_len = aad_len + aad_pad + ciphertext_len + ct_pad + 16;
    
    uint8_t *poly_buf = (uint8_t *)calloc(1, poly_len);
    if (!poly_buf) return -1;
    
    size_t offset = 0;
    if (aad && aad_len > 0) {
        memcpy(poly_buf + offset, aad, aad_len);
    }
    offset += aad_len + aad_pad;
    
    if (ciphertext && ciphertext_len > 0) {
        memcpy(poly_buf + offset, ciphertext, ciphertext_len);
    }
    offset += ciphertext_len + ct_pad;
    
    store64_le(poly_buf + offset, (uint64_t)aad_len);
    offset += 8;
    store64_le(poly_buf + offset, (uint64_t)ciphertext_len);
    offset += 8;
    
    uint8_t calc_tag[16];
    crypto_onetimeauth(calc_tag, poly_buf, poly_len, otk);
    free(poly_buf);
    
    // Constant time compare
    uint8_t diff = 0;
    for (int i = 0; i < 16; i++) {
        diff |= (calc_tag[i] ^ tag[i]);
    }
    if (diff != 0) {
        return -1; // Authentication failure
    }
    
    // 3. Decrypt ciphertext with counter = 1
    if (ciphertext_len > 0 && ciphertext && plaintext) {
        chacha20_xor(key, 1, nonce, ciphertext, ciphertext_len, plaintext);
    }
    return 0;
}

// -----------------------------------------------------------------------------
// Rolling Companion Link Cipher
// -----------------------------------------------------------------------------
void atr_cipher_init(ATRCompanionCipher *cipher, const uint8_t out_key[32], const uint8_t in_key[32]) {
    memcpy(cipher->out_key, out_key, 32);
    memcpy(cipher->in_key, in_key, 32);
    cipher->out_counter = 0;
    cipher->in_counter = 0;
}

int atr_cipher_encrypt_packet(ATRCompanionCipher *cipher, const uint8_t *header, size_t header_len, const uint8_t *payload, size_t payload_len, uint8_t *out_encrypted, uint8_t out_tag[16]) {
    // Companion Link Nonce: 8-byte little-endian counter + 4 zero bytes (12 bytes total)
    uint8_t nonce[12] = {0};
    store64_le(nonce, cipher->out_counter);
    cipher->out_counter++;
    
    return atr_chacha20_poly1305_encrypt(cipher->out_key, nonce, header, header_len, payload, payload_len, out_encrypted, out_tag);
}

int atr_cipher_decrypt_packet(ATRCompanionCipher *cipher, const uint8_t *header, size_t header_len, const uint8_t *in_encrypted, size_t in_len, const uint8_t in_tag[16], uint8_t *out_decrypted) {
    // Companion Link Nonce: 8-byte little-endian counter + 4 zero bytes (12 bytes total)
    uint8_t nonce[12] = {0};
    store64_le(nonce, cipher->in_counter);
    cipher->in_counter++;
    
    return atr_chacha20_poly1305_decrypt(cipher->in_key, nonce, header, header_len, in_encrypted, in_len, in_tag, out_decrypted);
}

// -----------------------------------------------------------------------------
// HMAC-SHA512 & HKDF-SHA512
// -----------------------------------------------------------------------------
void atr_hmac_sha512(const uint8_t *key, size_t key_len, const uint8_t *msg, size_t msg_len, uint8_t out[64]) {
    uint8_t k_block[128] = {0};
    if (key_len > 128) {
        crypto_hash_sha512(k_block, key, key_len);
    } else if (key && key_len > 0) {
        memcpy(k_block, key, key_len);
    }
    
    uint8_t ipad_buf[128 + msg_len];
    for (int i = 0; i < 128; i++) {
        ipad_buf[i] = k_block[i] ^ 0x36;
    }
    if (msg && msg_len > 0) {
        memcpy(ipad_buf + 128, msg, msg_len);
    }
    
    uint8_t inner_hash[64];
    crypto_hash_sha512(inner_hash, ipad_buf, 128 + msg_len);
    
    uint8_t opad_buf[128 + 64];
    for (int i = 0; i < 128; i++) {
        opad_buf[i] = k_block[i] ^ 0x5c;
    }
    memcpy(opad_buf + 128, inner_hash, 64);
    
    crypto_hash_sha512(out, opad_buf, 128 + 64);
}

void atr_hkdf_sha512(const uint8_t *salt, size_t salt_len, const uint8_t *info, size_t info_len, const uint8_t *ikm, size_t ikm_len, uint8_t out_key[32]) {
    // 1. HKDF-Extract: PRK = HMAC-SHA512(salt, ikm)
    uint8_t prk[64];
    if (!salt || salt_len == 0) {
        uint8_t zero_salt[64] = {0};
        atr_hmac_sha512(zero_salt, 64, ikm, ikm_len, prk);
    } else {
        atr_hmac_sha512(salt, salt_len, ikm, ikm_len, prk);
    }
    
    // 2. HKDF-Expand (for 32 bytes output): T(1) = HMAC-SHA512(PRK, info || 0x01)
    uint8_t info_buf[info_len + 1];
    if (info && info_len > 0) {
        memcpy(info_buf, info, info_len);
    }
    info_buf[info_len] = 0x01;
    
    uint8_t full_derived[64];
    atr_hmac_sha512(prk, 64, info_buf, info_len + 1, full_derived);
    
    memcpy(out_key, full_derived, 32);
}
