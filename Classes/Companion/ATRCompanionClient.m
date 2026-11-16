#import "ATRCompanionClient.h"
#import "ATROpack.h"
#import "Crypto/atr_chacha20_poly1305.h"
#import "Crypto/tweetnacl.h"

extern void randombytes(unsigned char *ptr, unsigned long long length);

#define TLV_TAG_METHOD        0x00
#define TLV_TAG_IDENTIFIER    0x01
#define TLV_TAG_SALT          0x02
#define TLV_TAG_PUBLIC_KEY    0x03
#define TLV_TAG_PROOF         0x04
#define TLV_TAG_ENCRYPTED     0x05
#define TLV_TAG_SEQ_NO        0x06
#define TLV_TAG_ERROR         0x07
#define TLV_TAG_SIGNATURE     0x0A

#define FRAME_PS_START 3
#define FRAME_PS_NEXT  4
#define FRAME_PV_START 5
#define FRAME_PV_NEXT  6
#define FRAME_U_OPACK  7
#define FRAME_E_OPACK  8
#define FRAME_P_OPACK  9

static NSString * const kATRCompanionCredentialsPrefKey = @"ATRCompanionCredentials";
static NSString * const kATRCompanionHostPrefKey        = @"ATRCompanionHost";
static NSString * const kATRCompanionPortPrefKey        = @"ATRCompanionPort";

static NSData *dataFromHex(NSString *hex) {
    if (!hex || [hex length] % 2 != 0) return nil;
    NSMutableData *d = [NSMutableData dataWithCapacity:[hex length] / 2];
    for (NSUInteger i = 0; i < [hex length]; i += 2) {
        NSString *sub = [hex substringWithRange:NSMakeRange(i, 2)];
        NSScanner *scanner = [NSScanner scannerWithString:sub];
        unsigned int val = 0;
        [scanner scanHexInt:&val];
        uint8_t b = (uint8_t)val;
        [d appendBytes:&b length:1];
    }
    return d;
}

static NSString *hexFromData(NSData *d) {
    const uint8_t *bytes = [d bytes];
    NSMutableString *hex = [NSMutableString stringWithCapacity:[d length] * 2];
    for (NSUInteger i = 0; i < [d length]; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return hex;
}

static NSData *writeTLV(NSDictionary *dict) {
    NSMutableData *res = [NSMutableData data];
    for (NSNumber *tagNum in dict) {
        uint8_t tag = [tagNum unsignedCharValue];
        NSData *val = [dict objectForKey:tagNum];
        if (![val isKindOfClass:[NSData class]]) continue;
        
        const uint8_t *bytes = [val bytes];
        NSUInteger remaining = [val length];
        while (remaining > 255) {
            uint8_t h[2] = {tag, 255};
            [res appendBytes:h length:2];
            [res appendBytes:bytes length:255];
            bytes += 255;
            remaining -= 255;
        }
        uint8_t h[2] = {tag, (uint8_t)remaining};
        [res appendBytes:h length:2];
        [res appendBytes:bytes length:remaining];
    }
    return res;
}

static NSDictionary *readTLV(NSData *data) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    const uint8_t *bytes = [data bytes];
    NSUInteger len = [data length];
    NSUInteger offset = 0;
    while (offset + 2 <= len) {
        uint8_t tag = bytes[offset++];
        uint8_t l = bytes[offset++];
        if (offset + l > len) break;
        NSData *chunk = [NSData dataWithBytes:bytes + offset length:l];
        offset += l;
        
        NSNumber *tagNum = [NSNumber numberWithUnsignedChar:tag];
        NSMutableData *existing = [dict objectForKey:tagNum];
        if (existing) {
            [existing appendData:chunk];
        } else {
            [dict setObject:[NSMutableData dataWithData:chunk] forKey:tagNum];
        }
    }
    return dict;
}

@interface ATRCompanionClient () {
    NSInputStream  *_inputStream;
    NSOutputStream *_outputStream;
    NSMutableData  *_incomingBuffer;
    NSMutableData  *_outgoingBuffer;
    NSMutableArray *_queuedCommands;
    
    // Pairing & Crypto state
    ATRCompanionCipher _cipher;
    BOOL _cipherActive;
    
    // Ephemeral verify state
    uint8_t _clientEphPriv[32];
    uint8_t _clientEphPub[32];
    uint8_t _sharedSecret[32];
    uint8_t _sessionKey[32];
    
    // Stored credentials
    NSData *_ltpk;      // Apple TV Ed25519 public key (32 bytes)
    NSData *_ltsk;      // Client Ed25519 secret seed (32 bytes)
    NSData *_atvId;     // Apple TV identifier
    NSData *_clientId;  // Client identifier
    
    uint32_t _xid;
    NSMutableDictionary *_responseCallbacks;
}

@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL isEncrypted;

@end

@implementation ATRCompanionClient

+ (ATRCompanionClient *)sharedClient {
    static ATRCompanionClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ATRCompanionClient alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _host = [defaults stringForKey:kATRCompanionHostPrefKey];
        if (!_host || [_host length] == 0) {
            _host = @"192.168.100.155";
        }
        _port = [defaults integerForKey:kATRCompanionPortPrefKey];
        if (_port == 0) {
            _port = 50590;
        }
        
        _incomingBuffer = [NSMutableData data];
        _outgoingBuffer = [NSMutableData data];
        _queuedCommands = [NSMutableArray array];
        _responseCallbacks = [NSMutableDictionary dictionary];
        _xid = (uint32_t)(arc4random() % 65535);
        _cipherActive = NO;
        
        NSString *savedCreds = [defaults stringForKey:kATRCompanionCredentialsPrefKey];
        if (savedCreds && [savedCreds length] > 0) {
            [self setCredentialsString:savedCreds];
        }
    }
    return self;
}

- (BOOL)isPaired {
    return (_ltpk && _ltsk && [_ltpk length] > 0 && [_ltsk length] > 0);
}

- (void)setCredentialsString:(NSString *)creds {
    if (!creds || [creds length] == 0) {
        [self clearCredentials];
        return;
    }
    NSArray *parts = [creds componentsSeparatedByString:@":"];
    if ([parts count] == 4) {
        _ltpk     = dataFromHex([parts objectAtIndex:0]);
        _ltsk     = dataFromHex([parts objectAtIndex:1]);
        _atvId    = dataFromHex([parts objectAtIndex:2]);
        _clientId = dataFromHex([parts objectAtIndex:3]);
        [[NSUserDefaults standardUserDefaults] setObject:creds forKey:kATRCompanionCredentialsPrefKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"[ATRCompanionClient] Loaded credentials successfully for ATV ID: %@", [[NSString alloc] initWithData:_atvId encoding:NSUTF8StringEncoding]);
    }
}

- (NSString *)getCredentialsString {
    if (![self isPaired]) return nil;
    return [NSString stringWithFormat:@"%@:%@:%@:%@",
            hexFromData(_ltpk),
            hexFromData(_ltsk),
            hexFromData(_atvId),
            hexFromData(_clientId)];
}

- (void)clearCredentials {
    _ltpk = nil;
    _ltsk = nil;
    _atvId = nil;
    _clientId = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kATRCompanionCredentialsPrefKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// -----------------------------------------------------------------------------
// Connection Management
// -----------------------------------------------------------------------------
- (void)connect {
    if (self.isConnected) return;
    
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.host, (UInt32)self.port, &readStream, &writeStream);
    
    _inputStream = (__bridge_transfer NSInputStream *)readStream;
    _outputStream = (__bridge_transfer NSOutputStream *)writeStream;
    
    [_inputStream setDelegate:self];
    [_outputStream setDelegate:self];
    
    [_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
    _cipherActive = NO;
    self.isEncrypted = NO;
    [_incomingBuffer setLength:0];
    [_outgoingBuffer setLength:0];
    
    [_inputStream open];
    [_outputStream open];
    
    if ([self.delegate respondsToSelector:@selector(companionClientStateChanged:)]) {
        [self.delegate companionClientStateChanged:@"Connecting..."];
    }
}

- (void)disconnect {
    if (_inputStream) {
        [_inputStream close];
        [_inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        _inputStream = nil;
    }
    if (_outputStream) {
        [_outputStream close];
        [_outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        _outputStream = nil;
    }
    self.isConnected = NO;
    self.isEncrypted = NO;
    _cipherActive = NO;
    [_queuedCommands removeAllObjects];
    
    if (_responseCallbacks && [_responseCallbacks count] > 0) {
        NSArray *cbs = [_responseCallbacks allValues];
        [_responseCallbacks removeAllObjects];
        for (void (^cb)(NSDictionary *, NSString *) in cbs) {
            cb(nil, @"Connection disconnected");
        }
    }
    
    if ([self.delegate respondsToSelector:@selector(companionClientDidDisconnect:)]) {
        [self.delegate companionClientDidDisconnect:nil];
    }
    if ([self.delegate respondsToSelector:@selector(companionClientStateChanged:)]) {
        [self.delegate companionClientStateChanged:@"Disconnected"];
    }
}

// -----------------------------------------------------------------------------
// Stream Delegate
// -----------------------------------------------------------------------------
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            if (aStream == _outputStream) {
                self.isConnected = YES;
                if ([self.delegate respondsToSelector:@selector(companionClientStateChanged:)]) {
                    [self.delegate companionClientStateChanged:@"Connected, Authenticating..."];
                }
                // If paired, start Pair-Verify immediately
                if ([self isPaired]) {
                    [self startPairVerify];
                }
            }
            break;
            
        case NSStreamEventHasBytesAvailable:
            if (aStream == _inputStream) {
                uint8_t buf[2048];
                NSInteger bytesRead = [_inputStream read:buf maxLength:sizeof(buf)];
                if (bytesRead > 0) {
                    [_incomingBuffer appendBytes:buf length:bytesRead];
                    [self processIncomingPackets];
                }
            }
            break;
            
        case NSStreamEventHasSpaceAvailable:
            if (aStream == _outputStream) {
                [self flushOutgoingBuffer];
            }
            break;
            
        case NSStreamEventErrorOccurred:
        case NSStreamEventEndEncountered: {
            NSError *err = [aStream streamError];
            [self disconnect];
            if ([self.delegate respondsToSelector:@selector(companionClientDidDisconnect:)]) {
                [self.delegate companionClientDidDisconnect:[err localizedDescription]];
            }
            break;
        }
        default:
            break;
    }
}

// -----------------------------------------------------------------------------
// Packet Processing & Framing
// -----------------------------------------------------------------------------
- (void)processIncomingPackets {
    while ([_incomingBuffer length] >= 4) {
        const uint8_t *bytes = [_incomingBuffer bytes];
        uint8_t frameType = bytes[0];
        uint32_t payloadLen = ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | (uint32_t)bytes[3];
        
        if ([_incomingBuffer length] < 4 + payloadLen) {
            break; // Wait for full frame
        }
        
        uint8_t header[4];
        memcpy(header, bytes, 4);
        
        NSData *payloadData = [NSData dataWithBytes:bytes + 4 length:payloadLen];
        [_incomingBuffer replaceBytesInRange:NSMakeRange(0, 4 + payloadLen) withBytes:NULL length:0];
        
        [self handleFrameType:frameType header:header payload:payloadData];
    }
}

- (void)handleFrameType:(uint8_t)frameType header:(const uint8_t *)header payload:(NSData *)payload {
    // Auth frames (PV_*, PS_*) are NEVER encrypted with the rolling session cipher!
    if (frameType == FRAME_PV_START || frameType == FRAME_PV_NEXT || frameType == FRAME_PS_START || frameType == FRAME_PS_NEXT) {
        id opackObj = [ATROpack unpack:payload];
        if ([opackObj isKindOfClass:[NSDictionary class]]) {
            if (frameType == FRAME_PV_NEXT) {
                [self handlePairVerifyResponse:(NSDictionary *)opackObj];
            }
        }
        return;
    }
    
    NSData *decryptedPayload = payload;
    if (_cipherActive && [payload length] >= 16) {
        size_t ctLen = [payload length] - 16;
        const uint8_t *rawPayload = [payload bytes];
        const uint8_t *ct = rawPayload;
        const uint8_t *tag = rawPayload + ctLen;
        
        uint8_t *decryptedBuf = (uint8_t *)malloc(ctLen > 0 ? ctLen : 1);
        int res = atr_cipher_decrypt_packet(&_cipher, header, 4, ct, ctLen, tag, decryptedBuf);
        if (res != 0) {
            free(decryptedBuf);
            NSLog(@"[ATRCompanionClient] AEAD Decrypt auth failed!");
            return;
        }
        decryptedPayload = [NSData dataWithBytesNoCopy:decryptedBuf length:ctLen freeWhenDone:YES];
    }
    
    id opackObj = [ATROpack unpack:decryptedPayload];
    if (!opackObj || ![opackObj isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *dict = (NSDictionary *)opackObj;
    NSLog(@"[ATRCompanionClient] Received frame %d payload: %@", frameType, dict);
    
    // Response or Event
    NSNumber *msgType = [dict objectForKey:@"_t"];
    NSNumber *xid = [dict objectForKey:@"_x"];
    
    // Check if this is a response (type 3, or has _rT) matching an outstanding request
    if ([msgType intValue] == 3 || [dict objectForKey:@"_rT"] != nil) {
        if (xid && _responseCallbacks) {
            void (^cb)(NSDictionary *, NSString *) = [_responseCallbacks objectForKey:xid];
            if (cb) {
                [_responseCallbacks removeObjectForKey:xid];
                NSDictionary *content = [dict objectForKey:@"_c"];
                cb(content, nil);
            }
        }
    } else if ([msgType intValue] == 1) { // Event
        NSString *identifier = [dict objectForKey:@"_i"];
        NSDictionary *content = [dict objectForKey:@"_c"];
        if ([identifier isEqualToString:@"_npI"] && content) {
            if ([self.delegate respondsToSelector:@selector(companionClientReceivedNowPlaying:)]) {
                [self.delegate companionClientReceivedNowPlaying:content];
            }
        }
    }
}

// -----------------------------------------------------------------------------
// Sending Frames
// -----------------------------------------------------------------------------
- (void)sendFrameType:(uint8_t)frameType opackDictionary:(NSDictionary *)dict {
    NSData *packed = [ATROpack pack:dict];
    size_t packedLen = [packed length];
    
    // Only encrypt if rolling cipher is active AND this is not an unencrypted auth frame
    BOOL shouldEncrypt = _cipherActive && (frameType != FRAME_PV_START && frameType != FRAME_PV_NEXT && frameType != FRAME_PS_START && frameType != FRAME_PS_NEXT);
    NSLog(@"[ATRCompanionClient] Sending frame %d (len=%lu, shouldEncrypt=%d, out_counter=%llu): %@", frameType, (unsigned long)packedLen, shouldEncrypt, self->_cipher.out_counter, [dict objectForKey:@"_i"] ?: dict);
    
    if (shouldEncrypt) {
        uint32_t payloadLen = (uint32_t)(packedLen + 16);
        uint8_t header[4];
        header[0] = frameType;
        header[1] = (uint8_t)((payloadLen >> 16) & 0xff);
        header[2] = (uint8_t)((payloadLen >> 8) & 0xff);
        header[3] = (uint8_t)(payloadLen & 0xff);
        
        uint8_t *encrypted = (uint8_t *)malloc(packedLen > 0 ? packedLen : 1);
        uint8_t tag[16];
        atr_cipher_encrypt_packet(&_cipher, header, 4, [packed bytes], packedLen, encrypted, tag);
        
        [_outgoingBuffer appendBytes:header length:4];
        if (packedLen > 0) {
            [_outgoingBuffer appendBytes:encrypted length:packedLen];
        }
        [_outgoingBuffer appendBytes:tag length:16];
        free(encrypted);
    } else {
        uint32_t payloadLen = (uint32_t)packedLen;
        uint8_t header[4];
        header[0] = frameType;
        header[1] = (uint8_t)((payloadLen >> 16) & 0xff);
        header[2] = (uint8_t)((payloadLen >> 8) & 0xff);
        header[3] = (uint8_t)(payloadLen & 0xff);
        
        [_outgoingBuffer appendBytes:header length:4];
        if (packedLen > 0) {
            [_outgoingBuffer appendData:packed];
        }
    }
    
    [self flushOutgoingBuffer];
}

- (void)flushOutgoingBuffer {
    if (!self.isConnected || !_outputStream || [_outgoingBuffer length] == 0) return;
    if (![_outputStream hasSpaceAvailable]) return;
    
    NSInteger written = [_outputStream write:[_outgoingBuffer bytes] maxLength:[_outgoingBuffer length]];
    if (written > 0) {
        [_outgoingBuffer replaceBytesInRange:NSMakeRange(0, written) withBytes:NULL length:0];
    }
}

// -----------------------------------------------------------------------------
// Pair-Verify Implementation
// -----------------------------------------------------------------------------
- (void)startPairVerify {
    randombytes(_clientEphPriv, 32);
    _clientEphPriv[0] &= 248;
    _clientEphPriv[31] &= 127;
    _clientEphPriv[31] |= 64;
    
    crypto_scalarmult_base(_clientEphPub, _clientEphPriv);
    
    NSData *pubData = [NSData dataWithBytes:_clientEphPub length:32];
    uint8_t seq1 = 1;
    NSData *seqData = [NSData dataWithBytes:&seq1 length:1];
    
    NSDictionary *tlvDict = @{
        [NSNumber numberWithUnsignedChar:TLV_TAG_SEQ_NO]: seqData,
        [NSNumber numberWithUnsignedChar:TLV_TAG_PUBLIC_KEY]: pubData
    };
    NSData *tlvData = writeTLV(tlvDict);
    
    _xid++;
    NSDictionary *msg = @{
        @"_pd": tlvData,
        @"_auTy": [NSNumber numberWithInt:4],
        @"_x": [NSNumber numberWithUnsignedInt:_xid]
    };
    [self sendFrameType:FRAME_PV_START opackDictionary:msg];
}

- (void)handlePairVerifyResponse:(NSDictionary *)dict {
    NSData *tlvData = [dict objectForKey:@"_pd"];
    if (!tlvData) return;
    
    NSDictionary *tlv = readTLV(tlvData);
    NSData *serverPub = [tlv objectForKey:[NSNumber numberWithUnsignedChar:TLV_TAG_PUBLIC_KEY]];
    NSData *encrypted = [tlv objectForKey:[NSNumber numberWithUnsignedChar:TLV_TAG_ENCRYPTED]];
    NSData *seqData = [tlv objectForKey:[NSNumber numberWithUnsignedChar:TLV_TAG_SEQ_NO]];
    uint8_t seq = (seqData && [seqData length] > 0) ? ((const uint8_t *)[seqData bytes])[0] : 0;
    
    // Stage 1: Apple TV sent SeqNo 2 with server public key & encrypted payload
    if (serverPub && encrypted && [serverPub length] >= 32 && [encrypted length] >= 16) {
        // Shared Secret via Curve25519
        crypto_scalarmult(_sharedSecret, _clientEphPriv, [serverPub bytes]);
        
        // HKDF-SHA512 for Pair-Verify session key
        atr_hkdf_sha512((const uint8_t *)"Pair-Verify-Encrypt-Salt", 24,
                        (const uint8_t *)"Pair-Verify-Encrypt-Info", 24,
                        _sharedSecret, 32, _sessionKey);
        
        // Decrypt server encrypted TLV (nonce = "PV-Msg02")
        size_t ctLen = [encrypted length] - 16;
        const uint8_t *ct = [encrypted bytes];
        const uint8_t *tag = [encrypted bytes] + ctLen;
        uint8_t nonce[12] = {0,0,0,0, 'P','V','-','M','s','g','0','2'};
        
        uint8_t *decrypted = (uint8_t *)malloc(ctLen);
        int res = atr_chacha20_poly1305_decrypt(_sessionKey, nonce, NULL, 0, ct, ctLen, tag, decrypted);
        if (res != 0) {
            free(decrypted);
            NSLog(@"[ATRCompanionClient] Server Pair-Verify decrypt failed!");
            return;
        }
        
        // Client response: Sign (client_eph_pub || client_id || server_pub) with client ltsk
        NSMutableData *deviceInfo = [NSMutableData dataWithBytes:_clientEphPub length:32];
        [deviceInfo appendData:_clientId];
        [deviceInfo appendData:serverPub];
        
        // Derive 64-byte secret key from 32-byte seed WITHOUT overwriting it!
        uint8_t sk64[64];
        uint8_t clientLtpk[32];
        crypto_sign_seed_keypair(clientLtpk, sk64, [_ltsk bytes]);
        
        unsigned long long smlen = 0;
        uint8_t *sm = (uint8_t *)malloc([deviceInfo length] + 64);
        crypto_sign_ed25519_tweet(sm, &smlen, [deviceInfo bytes], [deviceInfo length], sk64);
        NSData *clientSig = [NSData dataWithBytes:sm length:64];
        free(sm);
        free(decrypted);
        
        // Inner TLV: {Identifier: client_id, Signature: clientSig}
        NSDictionary *innerRespTlv = @{
            [NSNumber numberWithUnsignedChar:TLV_TAG_IDENTIFIER]: _clientId,
            [NSNumber numberWithUnsignedChar:TLV_TAG_SIGNATURE]: clientSig
        };
        NSData *rawInnerTlv = writeTLV(innerRespTlv);
        
        // Encrypt inner TLV with nonce = "PV-Msg03"
        uint8_t nonce3[12] = {0,0,0,0, 'P','V','-','M','s','g','0','3'};
        uint8_t *encResp = (uint8_t *)malloc([rawInnerTlv length]);
        uint8_t tag3[16];
        atr_chacha20_poly1305_encrypt(_sessionKey, nonce3, NULL, 0, [rawInnerTlv bytes], [rawInnerTlv length], encResp, tag3);
        
        NSMutableData *encDataWithTag = [NSMutableData dataWithBytes:encResp length:[rawInnerTlv length]];
        [encDataWithTag appendBytes:tag3 length:16];
        free(encResp);
        
        // Outer TLV: {SeqNo: 3, EncryptedData: encDataWithTag}
        uint8_t seq3 = 3;
        NSDictionary *outerRespTlv = @{
            [NSNumber numberWithUnsignedChar:TLV_TAG_SEQ_NO]: [NSData dataWithBytes:&seq3 length:1],
            [NSNumber numberWithUnsignedChar:TLV_TAG_ENCRYPTED]: encDataWithTag
        };
        NSData *rawOuterTlv = writeTLV(outerRespTlv);
        
        _xid++;
        NSDictionary *finalMsg = @{
            @"_pd": rawOuterTlv,
            @"_x": [NSNumber numberWithUnsignedInt:_xid]
        };
        [self sendFrameType:FRAME_PV_NEXT opackDictionary:finalMsg];
        return;
    }
    
    // Stage 2: Apple TV sent SeqNo 4 confirmation!
    if (seq == 4) {
        // Derive main communication keys
        uint8_t outKey[32];
        uint8_t inKey[32];
        atr_hkdf_sha512(NULL, 0, (const uint8_t *)"ClientEncrypt-main", 18, _sharedSecret, 32, outKey);
        atr_hkdf_sha512(NULL, 0, (const uint8_t *)"ServerEncrypt-main", 18, _sharedSecret, 32, inKey);
        
        atr_cipher_init(&_cipher, outKey, inKey);
        _cipherActive = YES;
        self.isEncrypted = YES;
        
        NSLog(@"[ATRCompanionClient] Pair-Verify completed! Encrypted session established.");
        
        // Register TV remote session with tvremoted!
        [self sendSessionHandshake];
        
        if ([self.delegate respondsToSelector:@selector(companionClientDidConnect)]) {
            [self.delegate companionClientDidConnect];
        }
        if ([self.delegate respondsToSelector:@selector(companionClientStateChanged:)]) {
            [self.delegate companionClientStateChanged:@"Connected (Direct Remote)"];
        }
        
        // Flush any queued button taps
        [self flushQueuedCommands];
    }
}

- (void)sendSessionHandshake {
    _xid++;
    // 1. _systemInfo
    NSDictionary *sysInfo = @{
        @"_i": @"_systemInfo",
        @"_t": [NSNumber numberWithInt:2],
        @"_x": [NSNumber numberWithUnsignedInt:_xid],
        @"_c": @{
            @"_bf": [NSNumber numberWithInt:0],
            @"_cf": [NSNumber numberWithInt:512],
            @"_clFl": [NSNumber numberWithInt:128],
            @"_sf": [NSNumber numberWithInt:256],
            @"_sv": @"170.18"
        }
    };
    [self sendFrameType:FRAME_E_OPACK opackDictionary:sysInfo];
    
    _xid++;
    // 2. _sessionStart for com.apple.tvremoteservices
    uint32_t sid = arc4random();
    NSDictionary *sessStart = @{
        @"_i": @"_sessionStart",
        @"_t": [NSNumber numberWithInt:2],
        @"_x": [NSNumber numberWithUnsignedInt:_xid],
        @"_c": @{
            @"_srvT": @"com.apple.tvremoteservices",
            @"_sid": [NSNumber numberWithUnsignedInt:sid]
        }
    };
    [self sendFrameType:FRAME_E_OPACK opackDictionary:sessStart];
    
    _xid++;
    // 3. TVRCSessionStart
    NSDictionary *tvrc = @{
        @"_i": @"TVRCSessionStart",
        @"_t": [NSNumber numberWithInt:2],
        @"_x": [NSNumber numberWithUnsignedInt:_xid],
        @"_c": @{
            @"ProtocolVersionKey": @"1.2"
        }
    };
    [self sendFrameType:FRAME_E_OPACK opackDictionary:tvrc];
    
    _xid++;
    // 4. Register interest in Now Playing events (_iMC)
    NSDictionary *interest = @{
        @"_i": @"_interest",
        @"_t": [NSNumber numberWithInt:1],
        @"_x": [NSNumber numberWithUnsignedInt:_xid],
        @"_c": @{
            @"_regEvents": @[@"_iMC"]
        }
    };
    [self sendFrameType:FRAME_E_OPACK opackDictionary:interest];
}

// -----------------------------------------------------------------------------
// HID Commands
// -----------------------------------------------------------------------------
- (void)sendHIDCommand:(ATRHIDCommand)command {
    NSLog(@"[ATRCompanionClient] sendHIDCommand: %ld (encrypted=%d)", (long)command, self.isEncrypted);
    if (!self.isEncrypted) {
        if (!_queuedCommands) {
            _queuedCommands = [NSMutableArray array];
        }
        [_queuedCommands addObject:[NSNumber numberWithInteger:command]];
        if (!self.isConnected) {
            [self connect];
        }
        return;
    }
    
    _xid++;
    // Button DOWN
    NSDictionary *downCmd = @{
        @"_t": [NSNumber numberWithInt:2],
        @"_i": @"_hidC",
        @"_x": [NSNumber numberWithUnsignedInt:_xid],
        @"_c": @{
            @"_hBtS": [NSNumber numberWithInt:1],
            @"_hidC": [NSNumber numberWithInteger:command]
        }
    };
    [self sendFrameType:FRAME_E_OPACK opackDictionary:downCmd];
    
    // Button UP after 60ms
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        self->_xid++;
        NSDictionary *upCmd = @{
            @"_t": [NSNumber numberWithInt:2],
            @"_i": @"_hidC",
            @"_x": [NSNumber numberWithUnsignedInt:self->_xid],
            @"_c": @{
                @"_hBtS": [NSNumber numberWithInt:2],
                @"_hidC": [NSNumber numberWithInteger:command]
            }
        };
        [self sendFrameType:FRAME_E_OPACK opackDictionary:upCmd];
    });
}

- (void)flushQueuedCommands {
    if (!_queuedCommands || [_queuedCommands count] == 0) return;
    NSArray *cmds = [NSArray arrayWithArray:_queuedCommands];
    [_queuedCommands removeAllObjects];
    for (NSNumber *num in cmds) {
        [self sendHIDCommand:[num integerValue]];
    }
}

- (void)sendHIDCommandNamed:(NSString *)name {
    NSString *n = [name lowercaseString];
    ATRHIDCommand cmd = ATRHIDCommandSelect;
    if ([n isEqualToString:@"up"]) cmd = ATRHIDCommandUp;
    else if ([n isEqualToString:@"down"]) cmd = ATRHIDCommandDown;
    else if ([n isEqualToString:@"left"]) cmd = ATRHIDCommandLeft;
    else if ([n isEqualToString:@"right"]) cmd = ATRHIDCommandRight;
    else if ([n isEqualToString:@"menu"] || [n isEqualToString:@"back"]) cmd = ATRHIDCommandMenu;
    else if ([n isEqualToString:@"select"] || [n isEqualToString:@"ok"]) cmd = ATRHIDCommandSelect;
    else if ([n isEqualToString:@"home"] || [n isEqualToString:@"top_menu"]) cmd = ATRHIDCommandHome;
    else if ([n isEqualToString:@"volume_up"]) cmd = ATRHIDCommandVolumeUp;
    else if ([n isEqualToString:@"volume_down"]) cmd = ATRHIDCommandVolumeDown;
    else if ([n isEqualToString:@"play"] || [n isEqualToString:@"pause"] || [n isEqualToString:@"play_pause"]) cmd = ATRHIDCommandPlayPause;
    else if ([n isEqualToString:@"sleep"]) cmd = ATRHIDCommandSleep;
    else if ([n isEqualToString:@"wake"]) cmd = ATRHIDCommandWake;
    else if ([n isEqualToString:@"screensaver"]) cmd = ATRHIDCommandScreensaver;
    
    [self sendHIDCommand:cmd];
}

// -----------------------------------------------------------------------------
// Import Credentials from Bridge
// -----------------------------------------------------------------------------
- (void)importCredentialsFromBridge:(NSString *)bridgeUrl completion:(void (^)(BOOL, NSString *))completion {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/credentials", bridgeUrl]];
    if (!url) {
        if (completion) completion(NO, @"Invalid Bridge URL");
        return;
    }
    
    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5.0];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError || !data) {
            if (completion) completion(NO, [connectionError localizedDescription] ?: @"No data received");
            return;
        }
        NSError *jsonErr = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        NSString *creds = [json objectForKey:@"credentials"];
        if (creds && [creds length] > 0) {
            [self setCredentialsString:creds];
            if (completion) completion(YES, @"Credentials imported successfully!");
        } else {
            if (completion) completion(NO, @"Bridge has no paired credentials yet. Pair on bridge first.");
        }
    }];
}

// -----------------------------------------------------------------------------
// App Discovery & Launching
// -----------------------------------------------------------------------------
- (void)sendRequest:(NSString *)identifier content:(NSDictionary *)content completion:(void (^)(NSDictionary *respContent, NSString *error))completion {
    if (!self.isEncrypted) {
        if (completion) completion(nil, @"Not connected");
        return;
    }
    _xid++;
    uint32_t currentXid = _xid;
    if (completion) {
        if (!_responseCallbacks) {
            _responseCallbacks = [[NSMutableDictionary alloc] init];
        }
        [_responseCallbacks setObject:[completion copy] forKey:[NSNumber numberWithUnsignedInt:currentXid]];
    }
    
    NSDictionary *dict = @{
        @"_i": identifier,
        @"_t": [NSNumber numberWithInt:2],
        @"_c": content ?: @{},
        @"_x": [NSNumber numberWithUnsignedInt:currentXid]
    };
    [self sendFrameType:FRAME_E_OPACK opackDictionary:dict];
}

- (void)fetchLaunchableApps:(void (^)(NSDictionary *apps, NSString *error))completion {
    [self sendRequest:@"FetchLaunchableApplicationsEvent" content:@{} completion:completion];
}

- (void)launchAppWithBundleID:(NSString *)bundleID {
    if (!bundleID) return;
    NSLog(@"[ATRCompanionClient] Launching app: %@", bundleID);
    [self sendRequest:@"_launchApp" content:@{ @"_bundleID": bundleID } completion:nil];
}

@end
