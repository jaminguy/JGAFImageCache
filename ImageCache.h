//
//  ImageCache.h
//  ImageCache
//
//  Created by Paresh Navadiya on 16/03/2016.
//  Copyright (c) 2013 Paresh Navadiya. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ImageCache : NSObject

#ifndef ImageCache_LOGGING_ENABLED
#define ImageCache_LOGGING_ENABLED 0
#endif

// When the app enters the background extra time will be requested within which to
// delete files from disk that are older than this number in seconds.
// Default is 7 days: -604800
#define ImageCache_DEFAULT_EXPIRATION_INTERVAL -604800
@property (assign, nonatomic) NSTimeInterval fileExpirationInterval;

// If the http response status code is not in the 400-499 range a retry can be initiated
// Default: 0
@property (assign, nonatomic) NSInteger maxNumberOfRetries;
// Number of seconds to wait between retries
// Default 0.0
@property (assign, nonatomic) NSTimeInterval retryDelay;

+ (nonnull ImageCache *)sharedInstance;
- (void)imageForURL:(nonnull NSString *)url completion:(void (^ __nullable)( UIImage * __nullable image))completion;
- (void)clearAllData;

@end
