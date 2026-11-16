#import "ATROpack.h"

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

static inline uint64_t load_le(const uint8_t *p, int bytes) {
    uint64_t val = 0;
    for (int i = 0; i < bytes; i++) {
        val |= ((uint64_t)p[i]) << (i * 8);
    }
    return val;
}

@implementation ATROpack

static void _packObject(id obj, NSMutableData *buffer, NSMutableArray *objectList) {
    if (!obj || [obj isKindOfClass:[NSNull class]]) {
        uint8_t b = 0x04;
        [buffer appendBytes:&b length:1];
        return;
    }
    
    if ([obj isKindOfClass:[NSNumber class]]) {
        NSNumber *num = (NSNumber *)obj;
        // Check for boolean
        CFTypeID typeId = CFGetTypeID((__bridge CFTypeRef)num);
        if (typeId == CFBooleanGetTypeID()) {
            uint8_t b = [num boolValue] ? 0x01 : 0x02;
            [buffer appendBytes:&b length:1];
            return;
        }
        
        const char *objCType = [num objCType];
        if (strcmp(objCType, "f") == 0 || strcmp(objCType, "d") == 0) {
            double d = [num doubleValue];
            uint8_t buf[9];
            buf[0] = 0x36;
            memcpy(buf + 1, &d, 8);
            [buffer appendBytes:buf length:9];
            return;
        }
        
        int64_t val = [num longLongValue];
        if (val >= 0 && val < 0x28) {
            uint8_t b = (uint8_t)(val + 8);
            [buffer appendBytes:&b length:1];
            return;
        } else if (val >= 0 && val <= 0xFF) {
            uint8_t buf[2] = {0x30, (uint8_t)val};
            [buffer appendBytes:buf length:2];
            return;
        } else if (val >= 0 && val <= 0xFFFF) {
            uint8_t buf[3] = {0x31, (uint8_t)(val & 0xFF), (uint8_t)((val >> 8) & 0xFF)};
            [buffer appendBytes:buf length:3];
            return;
        } else if (val >= 0 && val <= 0xFFFFFFFF) {
            uint8_t buf[5];
            buf[0] = 0x32;
            store32_le(buf + 1, (uint32_t)val);
            [buffer appendBytes:buf length:5];
            return;
        } else {
            uint8_t buf[9];
            buf[0] = 0x33;
            store64_le(buf + 1, (uint64_t)val);
            [buffer appendBytes:buf length:9];
            return;
        }
    }
    
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *str = (NSString *)obj;
        NSData *utf8 = [str dataUsingEncoding:NSUTF8StringEncoding];
        
        NSUInteger idx = [objectList indexOfObject:str];
        if (idx != NSNotFound) {
            if (idx < 0x21) {
                uint8_t b = (uint8_t)(0xA0 + idx);
                [buffer appendBytes:&b length:1];
                return;
            } else if (idx <= 0xFF) {
                uint8_t buf[2] = {0xC1, (uint8_t)idx};
                [buffer appendBytes:buf length:2];
                return;
            } else if (idx <= 0xFFFF) {
                uint8_t buf[3] = {0xC2, (uint8_t)(idx & 0xFF), (uint8_t)((idx >> 8) & 0xFF)};
                [buffer appendBytes:buf length:3];
                return;
            } else {
                uint8_t buf[5];
                buf[0] = 0xC3;
                store32_le(buf + 1, (uint32_t)idx);
                [buffer appendBytes:buf length:5];
                return;
            }
        }
        
        [objectList addObject:str];
        NSUInteger len = [utf8 length];
        if (len <= 0x20) {
            uint8_t b = (uint8_t)(0x40 + len);
            [buffer appendBytes:&b length:1];
            [buffer appendData:utf8];
        } else if (len <= 0xFF) {
            uint8_t buf[2] = {0x61, (uint8_t)len};
            [buffer appendBytes:buf length:2];
            [buffer appendData:utf8];
        } else if (len <= 0xFFFF) {
            uint8_t buf[3] = {0x62, (uint8_t)(len & 0xFF), (uint8_t)((len >> 8) & 0xFF)};
            [buffer appendBytes:buf length:3];
            [buffer appendData:utf8];
        } else {
            uint8_t buf[5];
            buf[0] = 0x64;
            store32_le(buf + 1, (uint32_t)len);
            [buffer appendBytes:buf length:5];
            [buffer appendData:utf8];
        }
        return;
    }
    
    if ([obj isKindOfClass:[NSData class]]) {
        NSData *data = (NSData *)obj;
        NSUInteger idx = [objectList indexOfObject:data];
        if (idx != NSNotFound) {
            if (idx < 0x21) {
                uint8_t b = (uint8_t)(0xA0 + idx);
                [buffer appendBytes:&b length:1];
                return;
            } else if (idx <= 0xFF) {
                uint8_t buf[2] = {0xC1, (uint8_t)idx};
                [buffer appendBytes:buf length:2];
                return;
            } else if (idx <= 0xFFFF) {
                uint8_t buf[3] = {0xC2, (uint8_t)(idx & 0xFF), (uint8_t)((idx >> 8) & 0xFF)};
                [buffer appendBytes:buf length:3];
                return;
            } else {
                uint8_t buf[5];
                buf[0] = 0xC3;
                store32_le(buf + 1, (uint32_t)idx);
                [buffer appendBytes:buf length:5];
                return;
            }
        }
        
        [objectList addObject:data];
        NSUInteger len = [data length];
        if (len <= 0x20) {
            uint8_t b = (uint8_t)(0x70 + len);
            [buffer appendBytes:&b length:1];
            [buffer appendData:data];
        } else if (len <= 0xFF) {
            uint8_t buf[2] = {0x91, (uint8_t)len};
            [buffer appendBytes:buf length:2];
            [buffer appendData:data];
        } else if (len <= 0xFFFF) {
            uint8_t buf[3] = {0x92, (uint8_t)(len & 0xFF), (uint8_t)((len >> 8) & 0xFF)};
            [buffer appendBytes:buf length:3];
            [buffer appendData:data];
        } else {
            uint8_t buf[5];
            buf[0] = 0x93;
            store32_le(buf + 1, (uint32_t)len);
            [buffer appendBytes:buf length:5];
            [buffer appendData:data];
        }
        return;
    }
    
    if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)obj;
        NSUInteger count = [arr count];
        uint8_t header = (uint8_t)(0xD0 + (count < 0x0F ? count : 0x0F));
        [buffer appendBytes:&header length:1];
        for (id item in arr) {
            _packObject(item, buffer, objectList);
        }
        if (count >= 0x0F) {
            uint8_t term = 0x03;
            [buffer appendBytes:&term length:1];
        }
        return;
    }
    
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        NSUInteger count = [dict count];
        uint8_t header = (uint8_t)(0xE0 + (count < 0x0F ? count : 0x0F));
        [buffer appendBytes:&header length:1];
        for (id key in dict) {
            _packObject(key, buffer, objectList);
            _packObject([dict objectForKey:key], buffer, objectList);
        }
        if (count >= 0x0F) {
            uint8_t term = 0x03;
            [buffer appendBytes:&term length:1];
        }
        return;
    }
}

+ (NSData *)pack:(id)obj {
    NSMutableData *buffer = [NSMutableData data];
    NSMutableArray *objectList = [NSMutableArray array];
    _packObject(obj, buffer, objectList);
    return buffer;
}

static id _unpackObject(const uint8_t *bytes, NSUInteger len, NSUInteger *offset, NSMutableArray *objectList) {
    if (*offset >= len) return nil;
    
    uint8_t tag = bytes[*offset];
    (*offset)++;
    
    if (tag == 0x01) {
        return (id)kCFBooleanTrue;
    } else if (tag == 0x02) {
        return (id)kCFBooleanFalse;
    } else if (tag == 0x04) {
        return [NSNull null];
    } else if (tag == 0x05) {
        if (*offset + 16 > len) return nil;
        NSData *uuid = [NSData dataWithBytes:bytes + *offset length:16];
        *offset += 16;
        return uuid;
    } else if (tag == 0x06) {
        if (*offset + 8 > len) return nil;
        uint64_t v = load_le(bytes + *offset, 8);
        *offset += 8;
        return [NSNumber numberWithUnsignedLongLong:v];
    } else if (tag >= 0x08 && tag <= 0x2F) {
        return [NSNumber numberWithInt:(int)(tag - 8)];
    } else if (tag == 0x35) {
        if (*offset + 4 > len) return nil;
        float f;
        memcpy(&f, bytes + *offset, 4);
        *offset += 4;
        return [NSNumber numberWithFloat:f];
    } else if (tag == 0x36) {
        if (*offset + 8 > len) return nil;
        double d;
        memcpy(&d, bytes + *offset, 8);
        *offset += 8;
        return [NSNumber numberWithDouble:d];
    } else if ((tag & 0xF0) == 0x30) {
        int noof_bytes = 1 << (tag & 0x0F);
        if (*offset + noof_bytes > len) return nil;
        uint64_t val = load_le(bytes + *offset, noof_bytes);
        *offset += noof_bytes;
        return [NSNumber numberWithLongLong:(int64_t)val];
    } else if (tag >= 0x40 && tag <= 0x60) {
        NSUInteger length = tag - 0x40;
        if (*offset + length > len) return nil;
        NSString *str = [[NSString alloc] initWithBytes:bytes + *offset length:length encoding:NSUTF8StringEncoding];
        *offset += length;
        if (str) {
            if (![objectList containsObject:str]) {
                [objectList addObject:str];
            }
            return str;
        }
        return @"";
    } else if (tag > 0x60 && tag <= 0x64) {
        int noof_bytes = tag & 0x0F;
        if (*offset + noof_bytes > len) return nil;
        uint64_t length = load_le(bytes + *offset, noof_bytes);
        *offset += noof_bytes;
        if (*offset + length > len) return nil;
        NSString *str = [[NSString alloc] initWithBytes:bytes + *offset length:(NSUInteger)length encoding:NSUTF8StringEncoding];
        *offset += (NSUInteger)length;
        if (str) {
            if (![objectList containsObject:str]) {
                [objectList addObject:str];
            }
            return str;
        }
        return @"";
    } else if (tag >= 0x70 && tag <= 0x90) {
        NSUInteger length = tag - 0x70;
        if (*offset + length > len) return nil;
        NSData *d = [NSData dataWithBytes:bytes + *offset length:length];
        *offset += length;
        if (![objectList containsObject:d]) {
            [objectList addObject:d];
        }
        return d;
    } else if (tag >= 0x91 && tag <= 0x94) {
        int noof_bytes = 1 << ((tag & 0x0F) - 1);
        if (*offset + noof_bytes > len) return nil;
        uint64_t length = load_le(bytes + *offset, noof_bytes);
        *offset += noof_bytes;
        if (*offset + length > len) return nil;
        NSData *d = [NSData dataWithBytes:bytes + *offset length:(NSUInteger)length];
        *offset += (NSUInteger)length;
        if (![objectList containsObject:d]) {
            [objectList addObject:d];
        }
        return d;
    } else if ((tag & 0xF0) == 0xD0) {
        uint8_t count = tag & 0x0F;
        NSMutableArray *arr = [NSMutableArray array];
        if (count == 0x0F) {
            while (*offset < len && bytes[*offset] != 0x03) {
                id elem = _unpackObject(bytes, len, offset, objectList);
                if (elem) [arr addObject:elem];
            }
            if (*offset < len && bytes[*offset] == 0x03) {
                (*offset)++;
            }
        } else {
            for (int i = 0; i < count && *offset < len; i++) {
                id elem = _unpackObject(bytes, len, offset, objectList);
                if (elem) [arr addObject:elem];
            }
        }
        return arr;
    } else if ((tag & 0xE0) == 0xE0) {
        uint8_t count = tag & 0x0F;
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        if (count == 0x0F) {
            while (*offset < len && bytes[*offset] != 0x03) {
                id k = _unpackObject(bytes, len, offset, objectList);
                id v = _unpackObject(bytes, len, offset, objectList);
                if (k && v) [dict setObject:v forKey:k];
            }
            if (*offset < len && bytes[*offset] == 0x03) {
                (*offset)++;
            }
        } else {
            for (int i = 0; i < count && *offset < len; i++) {
                id k = _unpackObject(bytes, len, offset, objectList);
                id v = _unpackObject(bytes, len, offset, objectList);
                if (k && v) [dict setObject:v forKey:k];
            }
        }
        return dict;
    } else if (tag >= 0xA0 && tag <= 0xC0) {
        NSUInteger index = tag - 0xA0;
        if (index < [objectList count]) {
            return [objectList objectAtIndex:index];
        }
        return nil;
    } else if (tag >= 0xC1 && tag <= 0xC4) {
        int noof_bytes = tag - 0xC0;
        if (*offset + noof_bytes > len) return nil;
        uint64_t uid = load_le(bytes + *offset, noof_bytes);
        *offset += noof_bytes;
        if (uid < [objectList count]) {
            return [objectList objectAtIndex:(NSUInteger)uid];
        }
        return nil;
    }
    
    return nil;
}

+ (id)unpack:(NSData *)data {
    if (!data || [data length] == 0) return nil;
    NSUInteger offset = 0;
    NSMutableArray *objectList = [NSMutableArray array];
    return _unpackObject([data bytes], [data length], &offset, objectList);
}

+ (id)unpackBytes:(const uint8_t *)bytes length:(NSUInteger)length consumed:(NSUInteger *)consumed {
    if (!bytes || length == 0) return nil;
    NSUInteger offset = 0;
    NSMutableArray *objectList = [NSMutableArray array];
    id res = _unpackObject(bytes, length, &offset, objectList);
    if (consumed) *consumed = offset;
    return res;
}

@end
