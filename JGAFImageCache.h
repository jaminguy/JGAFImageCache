//
//  JGUYImageCache.h
//  ImageCache
//
//  Created by Jamin Guy on 3/28/13.
//  Copyright (c) 2013 Jamin Guy. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface JGAFImageCache : NSObject

//default is 7 days
@property (assign, nonatomic) NSTimeInterval fileExpirationInterval;

+ (JGAFImageCache *)sharedInstance;
- (void)imageForURL:(NSString *)url completion:(void (^)(UIImage *image))completion;

@end
