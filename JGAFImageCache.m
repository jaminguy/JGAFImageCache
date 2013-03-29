//
//  JGUYImageCache.m
//  ImageCache
//
//  Created by Jamin Guy on 3/28/13.
//  Copyright (c) 2013 Jamin Guy. All rights reserved.
//

#import "JGAFImageCache.h"

#import <UIKit/UIKit.h>

#import "AFNetworking.h"
#import "NSString+JGAFSHA1.h"

@interface JGAFImageCache ()

@property (strong, nonatomic) NSCache *imageCache;
@property (strong, nonatomic) NSCache *httpClientCache;

@end

@implementation JGAFImageCache

+ (JGAFImageCache *)sharedInstance {
    static id sharedID;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedID = [[self alloc] init];
    });
    return sharedID;
}

- (id)init {
    self = [super init];
    if(self) {
        //default 7 days
        _fileExpirationInterval = -604800;
        _imageCache = [[NSCache alloc] init];
        _httpClientCache = [[NSCache alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    UIBackgroundTaskIdentifier backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    backgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
    }];
    
    if(backgroundTaskIdentifier != UIBackgroundTaskInvalid) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSDate *maxAge = [NSDate dateWithTimeIntervalSinceNow:_fileExpirationInterval];
            [JGAFImageCache removeAllFilesOlderThanDate:maxAge];
            [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
        });
    }
}

- (void)imageForURL:(NSString *)url completion:(void (^)(UIImage *image))completion {
    __weak JGAFImageCache *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *sha1 = [url jgaf_sha1];
        UIImage *image = [_imageCache objectForKey:sha1];
        if(image == nil) {
            image = [weakSelf imageFromDiskForKey:sha1];
        }
        
        if(image) {
            if(completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(image);
                });
            }
        }
        else {
            [weakSelf loadRemoteImageForURL:url key:sha1 completion:completion];
        }
    });
}

- (UIImage *)imageFromDiskForKey:(NSString *)key {
    UIImage *image = nil;
    @try {
        NSString *filePath = [JGAFImageCache filePathForKey:key];
        NSFileManager *fileManager = [JGAFImageCache sharedFileManager];
        if([fileManager fileExistsAtPath:filePath]) {
            NSData *imageData = [fileManager contentsAtPath:filePath];
            if(imageData) {
                [fileManager setAttributes:@{NSFileModificationDate:[NSDate date]} ofItemAtPath:filePath error:NULL];
                image = [[UIImage alloc] initWithData:imageData];
                if (image) {
                    [_imageCache setObject:image forKey:key];
                }
            }
            
        }
    }
    @catch(NSException *exception) {
        NSLog(@"%s [Line %d] %@", __PRETTY_FUNCTION__, __LINE__, exception);
        image = nil;
    }
    return image;
}

- (AFHTTPClient *)httpClientForBaseURL:(NSString *)baseURL {
    AFHTTPClient *httpClient;
    @synchronized(self) {
        NSString *key = [baseURL jgaf_sha1];
        httpClient = [_httpClientCache objectForKey:key];
        if(httpClient == nil) {
            httpClient = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString:baseURL]];
            [_httpClientCache setObject:httpClient forKey:key];
        }
    }
    return httpClient;
}

- (void)loadRemoteImageForURL:(NSString *)url key:(NSString *)key completion:(void (^)(UIImage *image))completion {
    NSURL *imageURL = [NSURL URLWithString:url];
    NSString *baseURL = [NSString stringWithFormat:@"%@://%@", imageURL.scheme, imageURL.host];
    NSString *imagePath = nil;
    if(imageURL.path.length) {
        imagePath = imageURL.path;
    }
    
    if(imageURL.query.length) {
        imagePath = [imagePath stringByAppendingFormat:@"?%@", imageURL.query];
    }
    
    if(imageURL.fragment.length) {
        imagePath = [imagePath stringByAppendingFormat:@"#%@", imageURL.fragment];
    }
    
    
    AFHTTPClient *httpClient = [self httpClientForBaseURL:baseURL];
    [httpClient
     getPath:imagePath
     parameters:nil
     success:^(AFHTTPRequestOperation *operation, id responseObject) {
         dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
             UIImage *image = nil;
             if(responseObject) {
                 @try {
                     image = [[UIImage alloc] initWithData:responseObject];
                 }
                 @catch(NSException *exception) {
                     NSLog(@"%s [Line %d] %@", __PRETTY_FUNCTION__, __LINE__, exception);
                     image = nil;
                 }
             }
             
             if(image) {
                 [JGAFImageCache saveImageToDiskForKey:image key:key];
                 [_imageCache setObject:image forKey:key];
                 
             }
             
             if(completion) {
                 dispatch_async(dispatch_get_main_queue(), ^{
                     completion(image);
                 });
             }
         });
     }
     failure:^(AFHTTPRequestOperation *operation, NSError *error) {
         NSLog(@"%s [Line %d] %@", __PRETTY_FUNCTION__, __LINE__, error);
         if(completion) {
             completion(nil);
         }
     }];
}

#pragma mark - Class Methods

+ (NSFileManager *)sharedFileManager {
    static id sharedFileManagerID;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedFileManagerID = [[NSFileManager alloc] init];
    });
    return sharedFileManagerID;
}

+ (NSString *)cacheDirectoryPath {
    static NSString *cacheDirectoryPath;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        cacheDirectoryPath = [[[caches objectAtIndex:0] stringByAppendingPathComponent:@"JGAFImageCache"] copy];
        NSFileManager *fileManager = [JGAFImageCache sharedFileManager];
        if([fileManager fileExistsAtPath:cacheDirectoryPath isDirectory:NULL] == NO) {
            [fileManager createDirectoryAtPath:cacheDirectoryPath withIntermediateDirectories:YES attributes:nil error:NULL];
        }
    });
    return cacheDirectoryPath;
}

+ (NSString *)filePathForKey:(NSString *)key {
    return [[JGAFImageCache cacheDirectoryPath] stringByAppendingPathComponent:key];
}

+ (void)saveImageToDiskForKey:(UIImage *)image key:(NSString *)key {
    @try {
        NSString *filePath = [JGAFImageCache filePathForKey:key];
        NSData *imageData = UIImagePNGRepresentation(image);
        [[JGAFImageCache sharedFileManager] createFileAtPath:filePath contents:imageData attributes:nil];
    }
    @catch(NSException *exception) {
        NSLog(@"%s [Line %d] %@", __PRETTY_FUNCTION__, __LINE__, exception);
    }
}

+ (void)removeAllFilesOlderThanDate:(NSDate *)date {
    NSFileManager *fileManager = [JGAFImageCache sharedFileManager];
    NSString *cachePath = [JGAFImageCache cacheDirectoryPath];
    NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtPath:cachePath];
    NSString *file;
    while (file = [directoryEnumerator nextObject]) {
        NSError *error = nil;
        NSString *filepath = [cachePath stringByAppendingPathComponent:file];
        NSDate *modifiedDate = [[fileManager attributesOfItemAtPath:filepath error:&error] fileModificationDate];
        if(error == nil) {
            if ([modifiedDate compare:date] == NSOrderedAscending) {
                [fileManager removeItemAtPath:filepath error:&error];
            }
        }
        
        if(error != nil) {
            NSLog(@"%s [Line %d] %@", __PRETTY_FUNCTION__, __LINE__, error);
        }
    }
}

@end
