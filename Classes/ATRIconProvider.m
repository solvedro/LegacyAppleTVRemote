#import "ATRIconProvider.h"
#import <QuartzCore/QuartzCore.h>

@implementation ATRIconProvider

static NSCache *sIconCache = nil;
static NSCache *sArtworkCache = nil;

+ (void)initialize {
    if (self == [ATRIconProvider class]) {
        sIconCache = [[NSCache alloc] init];
        [sIconCache setCountLimit:100];
        sArtworkCache = [[NSCache alloc] init];
        [sArtworkCache setCountLimit:50];
    }
}

+ (UIImage *)iconForBundleID:(NSString *)bundleID name:(NSString *)name size:(CGSize)size {
    if (!bundleID) bundleID = name ?: @"";
    NSString *cacheKey = [NSString stringWithFormat:@"%@_%.0fx%.0f", bundleID, size.width, size.height];
    UIImage *cached = [sIconCache objectForKey:cacheKey];
    if (cached) return cached;
    
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return nil;
    
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    CGFloat cornerRadius = size.width * 0.22; // iOS squircle proportion
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:cornerRadius];
    [path addClip];
    
    NSString *lowerBundle = [bundleID lowercaseString];
    NSString *lowerName = [name lowercaseString];
    
    if ([lowerBundle rangeOfString:@"youtube"].location != NSNotFound || [lowerName rangeOfString:@"youtube"].location != NSNotFound) {
        // YouTube: Vibrant Red with White Play Triangle
        CGContextSetRGBFillColor(ctx, 0.90, 0.12, 0.12, 1.0);
        CGContextFillRect(ctx, rect);
        
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
        CGFloat triW = size.width * 0.35;
        CGFloat triH = size.height * 0.38;
        CGFloat triX = (size.width - triW) / 2.0 + (size.width * 0.04);
        CGFloat triY = (size.height - triH) / 2.0;
        
        CGMutablePathRef tri = CGPathCreateMutable();
        CGPathMoveToPoint(tri, NULL, triX, triY);
        CGPathAddLineToPoint(tri, NULL, triX + triW, triY + triH / 2.0);
        CGPathAddLineToPoint(tri, NULL, triX, triY + triH);
        CGPathCloseSubpath(tri);
        CGContextAddPath(ctx, tri);
        CGContextFillPath(ctx);
        CGPathRelease(tri);
        
    } else if ([lowerBundle rangeOfString:@"netflix"].location != NSNotFound || [lowerName rangeOfString:@"netflix"].location != NSNotFound) {
        // Netflix: Dark background with Bold Red 'N'
        CGContextSetRGBFillColor(ctx, 0.08, 0.08, 0.08, 1.0);
        CGContextFillRect(ctx, rect);
        
        CGContextSetRGBFillColor(ctx, 0.89, 0.04, 0.08, 1.0);
        UIFont *f = [UIFont fontWithName:@"HelveticaNeue-Bold" size:size.height * 0.65] ?: [UIFont boldSystemFontOfSize:size.height * 0.65];
        NSString *letter = @"N";
        CGSize strSz = [letter sizeWithFont:f];
        [letter drawAtPoint:CGPointMake((size.width - strSz.width) / 2.0, (size.height - strSz.height) / 2.0) withFont:f];
        
    } else if ([lowerBundle rangeOfString:@"amazon"].location != NSNotFound || [lowerBundle rangeOfString:@"prime"].location != NSNotFound || [lowerName rangeOfString:@"prime"].location != NSNotFound) {
        // Prime Video: Deep Cyan-Navy
        CGContextSetRGBFillColor(ctx, 0.06, 0.15, 0.24, 1.0);
        CGContextFillRect(ctx, rect);
        
        CGContextSetRGBFillColor(ctx, 0.0, 0.66, 0.88, 1.0);
        UIFont *f = [UIFont fontWithName:@"HelveticaNeue-Bold" size:size.height * 0.40] ?: [UIFont boldSystemFontOfSize:size.height * 0.40];
        NSString *text = @"prime";
        CGSize strSz = [text sizeWithFont:f];
        [text drawAtPoint:CGPointMake((size.width - strSz.width) / 2.0, size.height * 0.18) withFont:f];
        
        // Smile smile curve
        CGContextSetRGBStrokeColor(ctx, 0.0, 0.66, 0.88, 1.0);
        CGContextSetLineWidth(ctx, size.width * 0.06);
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, size.width * 0.22, size.height * 0.72);
        CGContextAddQuadCurveToPoint(ctx, size.width * 0.50, size.height * 0.88, size.width * 0.78, size.height * 0.72);
        CGContextStrokePath(ctx);
        
    } else if ([lowerBundle rangeOfString:@"plex"].location != NSNotFound || [lowerName rangeOfString:@"plex"].location != NSNotFound) {
        // Plex: Charcoal with Amber Chevron
        CGContextSetRGBFillColor(ctx, 0.16, 0.16, 0.17, 1.0);
        CGContextFillRect(ctx, rect);
        
        CGContextSetRGBStrokeColor(ctx, 0.90, 0.63, 0.05, 1.0);
        CGContextSetLineWidth(ctx, size.width * 0.12);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, size.width * 0.38, size.height * 0.26);
        CGContextAddLineToPoint(ctx, size.width * 0.64, size.height * 0.50);
        CGContextAddLineToPoint(ctx, size.width * 0.38, size.height * 0.74);
        CGContextStrokePath(ctx);
        
    } else if ([lowerBundle rangeOfString:@"vlc"].location != NSNotFound || [lowerName rangeOfString:@"vlc"].location != NSNotFound) {
        // VLC: Traffic Cone Orange & White
        CGContextSetRGBFillColor(ctx, 0.96, 0.44, 0.0, 1.0);
        CGContextFillRect(ctx, rect);
        
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.95);
        CGContextFillRect(ctx, CGRectMake(0, size.height * 0.38, size.width, size.height * 0.14));
        CGContextFillRect(ctx, CGRectMake(0, size.height * 0.66, size.width, size.height * 0.14));
        
    } else if ([lowerBundle rangeOfString:@"retroarch"].location != NSNotFound || [lowerName rangeOfString:@"retroarch"].location != NSNotFound) {
        // RetroArch: Dark Grey with Neon Green Pixels
        CGContextSetRGBFillColor(ctx, 0.18, 0.18, 0.20, 1.0);
        CGContextFillRect(ctx, rect);
        
        CGContextSetRGBFillColor(ctx, 0.35, 1.0, 0.35, 1.0);
        UIFont *f = [UIFont boldSystemFontOfSize:size.height * 0.44];
        NSString *icon = @"👾";
        CGSize strSz = [icon sizeWithFont:f];
        [icon drawAtPoint:CGPointMake((size.width - strSz.width) / 2.0, (size.height - strSz.height) / 2.0) withFont:f];
        
    } else if ([lowerBundle rangeOfString:@"digi"].location != NSNotFound || [lowerName rangeOfString:@"digi"].location != NSNotFound) {
        // DIGI TV: Electric Blue with White 'D'
        CGContextSetRGBFillColor(ctx, 0.0, 0.38, 0.78, 1.0);
        CGContextFillRect(ctx, rect);
        
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
        UIFont *f = [UIFont fontWithName:@"HelveticaNeue-Bold" size:size.height * 0.60] ?: [UIFont boldSystemFontOfSize:size.height * 0.60];
        NSString *letter = @"D";
        CGSize strSz = [letter sizeWithFont:f];
        [letter drawAtPoint:CGPointMake((size.width - strSz.width) / 2.0, (size.height - strSz.height) / 2.0) withFont:f];
        
    } else if ([lowerBundle rangeOfString:@"moonlight"].location != NSNotFound || [lowerName rangeOfString:@"moonlight"].location != NSNotFound) {
        // Moonlight: Deep Space Navy with Crescent Moon
        CGContextSetRGBFillColor(ctx, 0.11, 0.13, 0.18, 1.0);
        CGContextFillRect(ctx, rect);
        
        CGContextSetRGBFillColor(ctx, 0.45, 0.78, 1.0, 1.0);
        UIFont *f = [UIFont boldSystemFontOfSize:size.height * 0.44];
        NSString *moon = @"🌙";
        CGSize strSz = [moon sizeWithFont:f];
        [moon drawAtPoint:CGPointMake((size.width - strSz.width) / 2.0, (size.height - strSz.height) / 2.0) withFont:f];
        
    } else if ([lowerBundle rangeOfString:@"music"].location != NSNotFound || [lowerName rangeOfString:@"music"].location != NSNotFound) {
        // Apple Music: Pink-Red Gradient
        CGContextSetRGBFillColor(ctx, 0.98, 0.22, 0.36, 1.0);
        CGContextFillRect(ctx, rect);
        
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
        UIFont *f = [UIFont boldSystemFontOfSize:size.height * 0.46];
        NSString *note = @"♫";
        CGSize strSz = [note sizeWithFont:f];
        [note drawAtPoint:CGPointMake((size.width - strSz.width) / 2.0, (size.height - strSz.height) / 2.0) withFont:f];
        
    } else if ([lowerBundle rangeOfString:@"podcasts"].location != NSNotFound || [lowerName rangeOfString:@"podcasts"].location != NSNotFound) {
        // Apple Podcasts: Purple
        CGContextSetRGBFillColor(ctx, 0.58, 0.21, 0.78, 1.0);
        CGContextFillRect(ctx, rect);
        
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
        UIFont *f = [UIFont boldSystemFontOfSize:size.height * 0.46];
        NSString *mic = @"🎙";
        CGSize strSz = [mic sizeWithFont:f];
        [mic drawAtPoint:CGPointMake((size.width - strSz.width) / 2.0, (size.height - strSz.height) / 2.0) withFont:f];
        
    } else if ([lowerBundle rangeOfString:@"appstore"].location != NSNotFound || [lowerName rangeOfString:@"app store"].location != NSNotFound) {
        // App Store: Blue with 'A'
        CGContextSetRGBFillColor(ctx, 0.10, 0.48, 0.92, 1.0);
        CGContextFillRect(ctx, rect);
        
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
        UIFont *f = [UIFont fontWithName:@"HelveticaNeue-Bold" size:size.height * 0.60] ?: [UIFont boldSystemFontOfSize:size.height * 0.60];
        NSString *a = @"A";
        CGSize strSz = [a sizeWithFont:f];
        [a drawAtPoint:CGPointMake((size.width - strSz.width) / 2.0, (size.height - strSz.height) / 2.0) withFont:f];
        
    } else if ([lowerBundle rangeOfString:@"settings"].location != NSNotFound || [lowerName rangeOfString:@"settings"].location != NSNotFound) {
        // Settings: Metallic Silver / Gear
        CGContextSetRGBFillColor(ctx, 0.35, 0.36, 0.38, 1.0);
        CGContextFillRect(ctx, rect);
        
        CGContextSetRGBFillColor(ctx, 0.90, 0.90, 0.92, 1.0);
        UIFont *f = [UIFont systemFontOfSize:size.height * 0.52];
        NSString *gear = @"⚙";
        CGSize strSz = [gear sizeWithFont:f];
        [gear drawAtPoint:CGPointMake((size.width - strSz.width) / 2.0, (size.height - strSz.height) / 2.0) withFont:f];
        
    } else {
        // Generic App: Distinct deterministic color palette based on hash of bundleID
        NSUInteger h = 0;
        for (NSUInteger i = 0; i < [bundleID length]; i++) {
            h = (h * 31) + [bundleID characterAtIndex:i];
        }
        
        CGFloat hue = (CGFloat)(h % 360) / 360.0;
        UIColor *bgColor = [UIColor colorWithHue:hue saturation:0.75 brightness:0.65 alpha:1.0];
        CGContextSetFillColorWithColor(ctx, bgColor.CGColor);
        CGContextFillRect(ctx, rect);
        
        // Draw Initial Letter
        NSString *initial = @"?";
        if ([name length] > 0) {
            initial = [[name substringToIndex:1] uppercaseString];
        } else if ([bundleID length] > 0) {
            NSArray *p = [bundleID componentsSeparatedByString:@"."];
            NSString *last = [p lastObject];
            if ([last length] > 0) initial = [[last substringToIndex:1] uppercaseString];
        }
        
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
        UIFont *f = [UIFont fontWithName:@"HelveticaNeue-Bold" size:size.height * 0.55] ?: [UIFont boldSystemFontOfSize:size.height * 0.55];
        CGSize strSz = [initial sizeWithFont:f];
        [initial drawAtPoint:CGPointMake((size.width - strSz.width) / 2.0, (size.height - strSz.height) / 2.0) withFont:f];
    }
    
    // Gloss & subtle border
    CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, 0.20);
    CGContextSetLineWidth(ctx, 1.0);
    [path stroke];
    
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    if (img) {
        [sIconCache setObject:img forKey:cacheKey];
    }
    return img;
}

+ (UIImage *)defaultThumbnailForMediaTitle:(NSString *)title artist:(NSString *)artist {
    CGSize size = CGSizeMake(44, 44);
    NSString *cacheKey = @"default_media_thumb";
    UIImage *cached = [sArtworkCache objectForKey:cacheKey];
    if (cached) return cached;
    
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:6.0];
    [path addClip];
    
    // Background dark gradient
    CGContextSetRGBFillColor(ctx, 0.18, 0.20, 0.24, 1.0);
    CGContextFillRect(ctx, rect);
    
    // Music/Film glyph
    CGContextSetRGBFillColor(ctx, 0.35, 0.75, 1.0, 1.0);
    UIFont *f = [UIFont boldSystemFontOfSize:22];
    NSString *glyph = @"♫";
    CGSize sz = [glyph sizeWithFont:f];
    [glyph drawAtPoint:CGPointMake((size.width - sz.width) / 2.0, (size.height - sz.height) / 2.0) withFont:f];
    
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    if (img) [sArtworkCache setObject:img forKey:cacheKey];
    return img;
}

+ (void)fetchArtworkForTitle:(NSString *)title artist:(NSString *)artist completion:(void (^)(UIImage *))completion {
    if (!completion) return;
    
    if ((!title || [title length] == 0) && (!artist || [artist length] == 0)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
        return;
    }
    
    NSString *query = [NSString stringWithFormat:@"%@ %@", title ?: @"", artist ?: @""];
    query = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *cacheKey = [NSString stringWithFormat:@"art_%@", query];
    
    UIImage *cached = [sArtworkCache objectForKey:cacheKey];
    if (cached) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(cached);
        });
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *escaped = [query stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *urlStr = [NSString stringWithFormat:@"https://itunes.apple.com/search?term=%@&media=all&limit=1", escaped];
        NSURL *url = [NSURL URLWithString:urlStr];
        
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:6.0];
        [req setValue:@"iTunes/12.6.5" forHTTPHeaderField:@"User-Agent"];
        
        NSURLResponse *resp = nil;
        NSError *err = nil;
        NSData *jsonData = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&err];
        
        NSString *artUrlStr = nil;
        if (!err && jsonData) {
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
            NSArray *results = [dict objectForKey:@"results"];
            if (results && [results count] > 0) {
                NSDictionary *first = [results objectAtIndex:0];
                artUrlStr = [first objectForKey:@"artworkUrl100"] ?: [first objectForKey:@"artworkUrl60"];
            }
        }
        
        UIImage *finalImage = nil;
        if (artUrlStr) {
            NSURL *imgUrl = [NSURL URLWithString:artUrlStr];
            NSData *imgData = [NSData dataWithContentsOfURL:imgUrl];
            if (imgData) {
                finalImage = [UIImage imageWithData:imgData];
            }
        }
        
        if (finalImage) {
            [sArtworkCache setObject:finalImage forKey:cacheKey];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(finalImage);
        });
    });
}

@end
