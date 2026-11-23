#import "ATRCompanionClient.h"
#import "ATROpack.h"
#import "Crypto/atr_chacha20_poly1305.h"
#import "Crypto/tweetnacl.h"
#import <CoreFoundation/CoreFoundation.h>

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

static NSData *ATRExtractSessionUUIDFromTiD(NSData *tiData) {
    if (!tiData || [tiData length] < 20) return nil;
    const uint8_t *bytes = (const uint8_t *)[tiData bytes];
    NSUInteger len = [tiData length];
    
    // Look for 0x4F 0x10 0x10 (Data object header for 16-byte session UUID in bplist)
    for (NSUInteger i = 0; i + 19 <= len; i++) {
        if (bytes[i] == 0x4F && bytes[i+1] == 0x10 && bytes[i+2] == 0x10) {
            return [NSData dataWithBytes:&bytes[i+3] length:16];
        }
    }
    return nil;
}

static NSData *ATRBuildRTITextPayload(NSData *sessionUUID, NSString *text) {
    if (!sessionUUID || [sessionUUID length] != 16 || !text) return nil;
    
    NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger textLen = [textData length];
    
    NSMutableData *outData = [NSMutableData dataWithBytes:"bplist00" length:8];
    NSMutableArray *offsets = [NSMutableArray arrayWithCapacity:40];
    
    void (^addObj)(const void *, NSUInteger) = ^(const void *bytes, NSUInteger len) {
        [offsets addObject:@([outData length])];
        [outData appendBytes:bytes length:len];
    };
    
    // Obj 0: top dict
    addObj("\xd4\x01\x02\x03\x04\x05\x06\x07\x0a", 9);
    // Obj 1: '$version'
    addObj("X$version", 9);
    // Obj 2: '$archiver'
    addObj("Y$archiver", 10);
    // Obj 3: '$top'
    addObj("T$top", 5);
    // Obj 4: '$objects'
    addObj("X$objects", 9);
    // Obj 5: int 100000
    addObj("\x12\x00\x01\x86\xa0", 5);
    // Obj 6: 'RTIKeyedArchiver'
    addObj("_\x10\x10RTIKeyedArchiver", 19);
    // Obj 7: dict len 1
    addObj("\xd1\x08\t", 3);
    // Obj 8: 'textOperations'
    addObj("^textOperations", 15);
    // Obj 9: UID 1
    addObj("\x80\x01", 2);
    // Obj 10: array len 8
    addObj("\xa8\x0b\x0c\x13\x17\x18\x1e\"%", 9);
    // Obj 11: '$null'
    addObj("U$null", 6);
    // Obj 12: dict len 3
    addObj("\xd3\r\x0e\x0f\x10\x11\x12", 7);
    // Obj 13: 'keyboardOutput'
    addObj("^keyboardOutput", 15);
    // Obj 14: '$class'
    addObj("V$class", 7);
    // Obj 15: 'targetSessionUUID'
    addObj("_\x10\x11targetSessionUUID", 20);
    // Obj 16: UID 2
    addObj("\x80\x02", 2);
    // Obj 17: UID 7
    addObj("\x80\x07", 2);
    // Obj 18: UID 5
    addObj("\x80\x05", 2);
    // Obj 19: dict len 2
    addObj("\xd2\x14\x0e\x15\x16", 5);
    // Obj 20: 'insertionText'
    addObj("]insertionText", 14);
    // Obj 21: UID 3
    addObj("\x80\x03", 2);
    // Obj 22: UID 4
    addObj("\x80\x04", 2);
    
    // Obj 23: string text
    if (textLen < 15) {
        uint8_t hdr = 0x50 | (uint8_t)textLen;
        NSMutableData *strObj = [NSMutableData dataWithBytes:&hdr length:1];
        [strObj appendData:textData];
        addObj([strObj bytes], [strObj length]);
    } else {
        uint8_t hdr[3] = { 0x5F, 0x10, (uint8_t)textLen };
        NSMutableData *strObj = [NSMutableData dataWithBytes:hdr length:3];
        [strObj appendData:textData];
        addObj([strObj bytes], [strObj length]);
    }
    
    // Obj 24: dict len 2
    addObj("\xd2\x19\x1a\x1b\x1c", 5);
    // Obj 25: '$classname'
    addObj("Z$classname", 11);
    // Obj 26: '$classes'
    addObj("X$classes", 9);
    // Obj 27: 'TIKeyboardOutput'
    addObj("_\x10\x10TIKeyboardOutput", 19);
    // Obj 28: array len 2
    addObj("\xa2\x1b\x1d", 3);
    // Obj 29: 'NSObject'
    addObj("XNSObject", 9);
    // Obj 30: dict len 2
    addObj("\xd2\x1f\x0e !", 5);
    // Obj 31: 'NS.uuidbytes'
    addObj("\\NS.uuidbytes", 13);
    
    // Obj 32: data len 16 (0x4f 0x10 0x10) + sessionUUID
    NSMutableData *uuidObj = [NSMutableData dataWithBytes:"O\x10\x10" length:3];
    [uuidObj appendData:sessionUUID];
    addObj([uuidObj bytes], [uuidObj length]);
    
    // Obj 33: UID 6
    addObj("\x80\x06", 2);
    // Obj 34: dict len 2
    addObj("\xd2\x19\x1a#$", 5);
    // Obj 35: 'NSUUID'
    addObj("VNSUUID", 7);
    // Obj 36: array len 2
    addObj("\xa2#\x1d", 3);
    // Obj 37: dict len 2
    addObj("\xd2\x19\x1a&'", 5);
    // Obj 38: 'RTITextOperations'
    addObj("_\x10\x11RTITextOperations", 20);
    // Obj 39: array len 2
    addObj("\xa2&\x1d", 3);
    
    if ([offsets count] != 40) return nil;
    uint64_t tableOffset = (uint64_t)[outData length];
    
    // Write 2-byte offsets
    for (NSNumber *n in offsets) {
        uint16_t off = CFSwapInt16HostToBig((uint16_t)[n unsignedShortValue]);
        [outData appendBytes:&off length:2];
    }
    
    // Write trailer (32 bytes)
    uint8_t trailer[32];
    memset(trailer, 0, 32);
    trailer[6] = 2; // offset_int_size = 2
    trailer[7] = 1; // object_ref_size = 1
    
    uint64_t numObj = CFSwapInt64HostToBig(40);
    memcpy(&trailer[8], &numObj, 8);
    
    uint64_t topObj = CFSwapInt64HostToBig(0);
    memcpy(&trailer[16], &topObj, 8);
    
    uint64_t offTable = CFSwapInt64HostToBig(tableOffset);
    memcpy(&trailer[24], &offTable, 8);
    
    [outData appendBytes:trailer length:32];
    return outData;
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
    NSData *_lastSessionUUID;
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
        } else {
            // Default pre-paired credentials for Apple TV 4K Living Room
            NSString *defaultCreds = @"bac81ced6140df7378653875bf63a9f5cc791f4c4744acd9a9e7f06cfc14388f:7fd4b0465e5ecb4de49e1b2a115c2df89dc4d67a45534b66bcab15741b35862a:35444646453032362d393034412d343936362d424133442d453738344344304345343030:64663365393030612d316537612d343531342d613636302d383164306432336163366635";
            [self setCredentialsString:defaultCreds];
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
    if (self.isConnected && self.isEncrypted) return;
    if (self.isConnected && !self.isEncrypted) {
        if ([self isPaired]) {
            [self startPairVerify];
        }
        return;
    }
    
    NSLog(@"[ATRCompanionClient] Connecting directly to Apple TV at %@:%ld...", self.host, (long)self.port);
    
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
        } else if ([identifier isEqualToString:@"_tiStarted"] || [identifier isEqualToString:@"_tiStart"]) {
            NSLog(@"[ATRCompanionClient] Text input session began on Apple TV");
            NSData *tiD = [content objectForKey:@"_tiD"];
            if (tiD && [tiD isKindOfClass:[NSData class]]) {
                NSData *uuid = ATRExtractSessionUUIDFromTiD(tiD);
                if (uuid) {
                    self->_lastSessionUUID = uuid;
                    NSLog(@"[ATRCompanionClient] Captured sessionUUID: %@", uuid);
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"ATRTextInputRequestedNotification" object:nil userInfo:content];
            });
        } else if ([identifier isEqualToString:@"_tiStopped"] || [identifier isEqualToString:@"_tiStop"]) {
            NSLog(@"[ATRCompanionClient] Text input session ended on Apple TV");
            self->_lastSessionUUID = nil;
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
    else if ([n isEqualToString:@"play"]) {
        [self sendMediaControlCommand:1 args:nil];
        return;
    }
    else if ([n isEqualToString:@"pause"]) {
        [self sendMediaControlCommand:2 args:nil];
        return;
    }
    else if ([n isEqualToString:@"play_pause"]) cmd = ATRHIDCommandPlayPause;
    else if ([n isEqualToString:@"sleep"]) cmd = ATRHIDCommandSleep;
    else if ([n isEqualToString:@"wake"]) cmd = ATRHIDCommandWake;
    else if ([n isEqualToString:@"screensaver"]) cmd = ATRHIDCommandScreensaver;
    else if ([n isEqualToString:@"siri"]) cmd = ATRHIDCommandSiri;
    else if ([n isEqualToString:@"control"] || [n isEqualToString:@"control_center"]) cmd = (ATRHIDCommand)19;
    else if ([n isEqualToString:@"search"]) {
        [self launchAppWithBundleID:@"com.apple.TVSearch"];
        return;
    }
    
    else if ([n isEqualToString:@"skip_forward"]) {
        [self skipForward:10.0];
        return;
    }
    else if ([n isEqualToString:@"skip_forward_15"]) {
        [self skipForward:15.0];
        return;
    }
    else if ([n isEqualToString:@"skip_backward"]) {
        [self skipBackward:10.0];
        return;
    }
    else if ([n isEqualToString:@"skip_backward_15"]) {
        [self skipBackward:15.0];
        return;
    }
    else if ([n isEqualToString:@"next"] || [n isEqualToString:@"next_track"]) {
        [self nextTrack];
        return;
    }
    else if ([n isEqualToString:@"previous"] || [n isEqualToString:@"previous_track"]) {
        [self previousTrack];
        return;
    }
    else if ([n isEqualToString:@"cc"] || [n isEqualToString:@"subtitles"]) {
        [self toggleSubtitles];
        return;
    }
    
    [self sendHIDCommand:cmd];
}

- (void)sendMediaControlCommand:(int)cmd args:(NSDictionary *)args {
    if (!self.isEncrypted) {
        if (!self.isConnected) [self connect];
        return;
    }
    NSMutableDictionary *c = [NSMutableDictionary dictionary];
    [c setObject:[NSNumber numberWithInt:cmd] forKey:@"_mcc"];
    if (args) {
        [c addEntriesFromDictionary:args];
    }
    [self sendRequest:@"_mcc" content:c completion:nil];
}

- (void)skipForward:(double)seconds {
    [self sendMediaControlCommand:7 args:@{ @"_skpS": [NSNumber numberWithDouble:(seconds > 0 ? seconds : 10.0)] }];
}

- (void)skipBackward:(double)seconds {
    [self sendMediaControlCommand:7 args:@{ @"_skpS": [NSNumber numberWithDouble:(seconds > 0 ? -seconds : -10.0)] }];
}

- (void)nextTrack {
    [self sendMediaControlCommand:3 args:nil];
}

- (void)previousTrack {
    [self sendMediaControlCommand:4 args:nil];
}

- (void)toggleSubtitles {
    [self sendRequest:@"_mcc" content:@{ @"_mcc": @12 } completion:^(NSDictionary *resp, NSString *err) {
        int current = [[resp objectForKey:@"_mcs"] intValue];
        int next = (current == 2) ? 1 : 2; // Toggle between 1 (Off) and 2 (On)
        [self sendMediaControlCommand:13 args:@{ @"_mcs": [NSNumber numberWithInt:next] }];
    }];
}

- (void)requestTextInputSession:(void (^)(BOOL ready))completion {
    if (!self.isEncrypted) {
        if (!self.isConnected) [self connect];
        if (completion) completion(NO);
        return;
    }
    [self sendRequest:@"_tiStart" content:@{} completion:^(NSDictionary *respContent, NSString *error) {
        if (respContent) {
            NSData *tiD = [respContent objectForKey:@"_tiD"];
            if (tiD && [tiD isKindOfClass:[NSData class]]) {
                NSData *uuid = ATRExtractSessionUUIDFromTiD(tiD);
                if (uuid) {
                    self->_lastSessionUUID = uuid;
                    NSLog(@"[ATRCompanionClient] _tiStart obtained sessionUUID: %@", uuid);
                    if (completion) completion(YES);
                    return;
                }
            }
        }
        if (completion) completion(NO);
    }];
}

- (void)sendTextInput:(NSString *)text {
    [self sendTextInput:text completion:nil];
}

- (void)sendTextInput:(NSString *)text completion:(void (^)(BOOL success, NSString *error))completion {
    if (!text || [text length] == 0) {
        if (completion) completion(NO, @"Empty text");
        return;
    }
    NSLog(@"[ATRCompanionClient] sendTextInput: %@", text);
    
    if (!self.isEncrypted) {
        if (!self.isConnected) [self connect];
        if (completion) completion(NO, @"Not connected");
        return;
    }
    
    void (^sendEventBlock)(NSData *uuid) = ^(NSData *uuid) {
        NSData *payload = ATRBuildRTITextPayload(uuid, text);
        if (!payload) {
            if (completion) completion(NO, @"Payload encoding failed");
            return;
        }
        
        self->_xid++;
        NSDictionary *tiEvent = @{
            @"_i": @"_tiC",
            @"_t": [NSNumber numberWithInt:1], // Event (type 1)
            @"_x": [NSNumber numberWithUnsignedInt:self->_xid],
            @"_c": @{
                @"_tiV": [NSNumber numberWithInt:1],
                @"_tiD": payload
            }
        };
        [self sendFrameType:FRAME_E_OPACK opackDictionary:tiEvent];
        if (completion) completion(YES, nil);
    };
    
    if (_lastSessionUUID && [_lastSessionUUID length] == 16) {
        sendEventBlock(_lastSessionUUID);
    } else {
        [self requestTextInputSession:^(BOOL ready) {
            if (ready && self->_lastSessionUUID) {
                sendEventBlock(self->_lastSessionUUID);
            } else {
                NSLog(@"[ATRCompanionClient] No active text input field on Apple TV");
                if (completion) completion(NO, @"No text field focused on TV");
            }
        }];
    }
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
