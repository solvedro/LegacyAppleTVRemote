#ifndef ATR_CHACHA20_POLY1305_H
#define ATR_CHACHA20_POLY1305_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ChaCha20-Poly1305 AEAD (RFC 8439 / RFC 7539)
// Key: 32 bytes (256 bits)
// Nonce: 12 bytes (96 bits)
// Tag: 16 bytes (128 bits)
int atr_chacha20_poly1305_encrypt(
    const uint8_t key[32],
    const uint8_t nonce[12],
    const uint8_t *aad, size_t aad_len,
    const uint8_t *plaintext, size_t plaintext_len,
    uint8_t *ciphertext,
    uint8_t tag[16]
);

int atr_chacha20_poly1305_decrypt(
    const uint8_t key[32],
    const uint8_t nonce[12],
    const uint8_t *aad, size_t aad_len,
    const uint8_t *ciphertext, size_t ciphertext_len,
    const uint8_t tag[16],
    uint8_t *plaintext
);

// Rolling cipher session state for Companion protocol
typedef struct {
    uint8_t out_key[32];
    uint8_t in_key[32];
    uint64_t out_counter;
    uint64_t in_counter;
} ATRCompanionCipher;

void atr_cipher_init(ATRCompanionCipher *cipher, const uint8_t out_key[32], const uint8_t in_key[32]);
int atr_cipher_encrypt_packet(ATRCompanionCipher *cipher, const uint8_t *header, size_t header_len, const uint8_t *payload, size_t payload_len, uint8_t *out_encrypted, uint8_t out_tag[16]);
int atr_cipher_decrypt_packet(ATRCompanionCipher *cipher, const uint8_t *header, size_t header_len, const uint8_t *in_encrypted, size_t in_len, const uint8_t in_tag[16], uint8_t *out_decrypted);

// HMAC-SHA512 & HKDF-SHA512 (RFC 5869)
void atr_hmac_sha512(const uint8_t *key, size_t key_len, const uint8_t *msg, size_t msg_len, uint8_t out[64]);
void atr_hkdf_sha512(const uint8_t *salt, size_t salt_len, const uint8_t *info, size_t info_len, const uint8_t *ikm, size_t ikm_len, uint8_t out_key[32]);

#ifdef __cplusplus
}
#endif

#endif // ATR_CHACHA20_POLY1305_H
