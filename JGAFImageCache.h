//
//  JGAFImageCache.h
//  JGAFImageCache
//
//  Created by Jamin Guy on 3/28/13.
//  Copyright (c) 2013 Jamin Guy. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface JGAFImageCache : NSObject

#ifndef JGAFImageCache_LOGGING_ENABLED
#define JGAFImageCache_LOGGING_ENABLED 0
#endif

// When the app enters the background extra time will be requested within which to
// delete files from disk that are older than this number in seconds.
// Default is 7 days: -604800
#define JGAFImageCache_DEFAULT_EXPIRATION_INTERVAL -604800
@property (assign, nonatomic) NSTimeInterval fileExpirationInterval;

// If the http response status code is not in the 400-499 range a retry can be initiated
// Default: 0
@property (assign, nonatomic) NSInteger maxNumberOfRetries;
// Number of seconds to wait between retries
// Default 0.0
@property (assign, nonatomic) NSTimeInterval retryDelay;

+ (JGAFImageCache *)sharedInstance;
- (void)imageForURL:(NSString *)url completion:(void (^)(UIImage *image))completion;
- (void)clearAllData;

@end
