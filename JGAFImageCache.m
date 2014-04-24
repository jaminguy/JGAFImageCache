//
//  JGAFImageCache.m
//  JGAFImageCache
//
//  Created by Jamin Guy on 3/28/13.
//  Copyright (c) 2013 Jamin Guy. All rights reserved.
//

#import "JGAFImageCache.h"

#import <UIKit/UIKit.h>

#import "NSString+JGAFSHA1.h"

@interface JGAFImageCache ()

@property (strong, nonatomic) NSCache *imageCache;
@property (strong, nonatomic) NSURLSession *urlSession;

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
        _fileExpirationInterval = JGAFImageCache_DEFAULT_EXPIRATION_INTERVAL;
        _imageCache = [[NSCache alloc] init];
        _maxNumberOfRetries = 0;
        _retryDelay = 0.0;
        
        NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:sessionConfiguration];
        _urlSession = urlSession;
        
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
        __weak JGAFImageCache *weakSelf = self;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSDate *maxAge = [NSDate dateWithTimeIntervalSinceNow:weakSelf.fileExpirationInterval];
            [[self class] removeAllFilesOlderThanDate:maxAge];
            [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
        });
    }
}

- (void)imageForURL:(NSString *)url completion:(void (^)(UIImage *image))completion {
    NSAssert(url.length > 0, @"url cannot be nil");
    __weak JGAFImageCache *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *sha1 = [url jgaf_sha1];
        UIImage *image = [weakSelf.imageCache objectForKey:sha1];
        if(image == nil) {
            image = [weakSelf imageFromDiskForKey:sha1];
        }
        
        if(image == nil) {
            [weakSelf loadRemoteImageForURL:url key:sha1 retryCount:0 completion:completion];
        }
        else if(completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(image);
            });
        }
    });
}

- (UIImage *)imageFromDiskForKey:(NSString *)key {
    UIImage *image = nil;
    @try {
        NSString *filePath = [[self class] filePathForKey:key];
        NSFileManager *fileManager = [[self class] sharedFileManager];
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
#if JGAFImageCache_LOGGING_ENABLED
        NSLog(@"%s [Line %d] %@", __PRETTY_FUNCTION__, __LINE__, exception);
#endif
    }
    return image;
}

- (void)loadRemoteImageForURL:(NSString *)url key:(NSString *)key retryCount:(NSInteger)retryCount completion:(void (^)(UIImage *image))completion {
    if (url.length > 0) {
        NSMutableURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
        __weak JGAFImageCache *weakSelf = self;
        NSURLSessionDataTask *task = [self.urlSession dataTaskWithRequest:urlRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSInteger httpStatusCode = httpResponse.statusCode;
            switch (httpStatusCode) {
                case 200: {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        UIImage *image = nil;
                        if(data.length) {
                            @try {
                                image = [[UIImage alloc] initWithData:data];
                            }
                            @catch(NSException *exception) {
#if JGAFImageCache_LOGGING_ENABLED
                                NSLog(@"%s [Line %d] %@", __PRETTY_FUNCTION__, __LINE__, exception);
#endif
                            }
                        }
                        
                        if(image) {
                            [[weakSelf class] saveImageToDiskForKey:image key:key];
                            [weakSelf.imageCache setObject:image forKey:key];
                            
                        }
                        
                        if(completion) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                completion(image);
                            });
                        }
                    });
                } break;
                    
                default: {
                    NSLog(@"%s [Line %d] failed: %@", __PRETTY_FUNCTION__, __LINE__, url);
                    if((retryCount >= weakSelf.maxNumberOfRetries) || (httpStatusCode >= 400 && httpStatusCode <= 499)) {
                        //out of retries or got a 400 level error so don't retry
                        if(completion) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                completion(nil);
                            });
                        }
                    }
                    else {
                        // try again
                        NSInteger nextRetryCount = retryCount + 1;
                        double delayInSeconds = self.retryDelay;
                        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                            [self loadRemoteImageForURL:url key:key retryCount:nextRetryCount completion:completion];
                        });
                        
#if JGAFImageCache_LOGGING_ENABLED
                        NSLog(@"%s [Line %d] retrying(%d)", __PRETTY_FUNCTION__, __LINE__, nextRetryCount);
#endif
                    }
                    
#if JGAFImageCache_LOGGING_ENABLED
                    NSLog(@"%s [Line %d] statusCode(%d) %@", __PRETTY_FUNCTION__, __LINE__, statusCode, error);
#endif
                } break;
            }
        }];
        [task resume];
    }
    else if(completion) {
        completion(nil);
    }
}

- (void)clearAllData {
    [self.imageCache removeAllObjects];
    
    UIBackgroundTaskIdentifier backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    backgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
    }];
    
    if(backgroundTaskIdentifier != UIBackgroundTaskInvalid) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[self class] removeAllFilesOlderThanDate:[NSDate date]];
            [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
        });
    }
}

#pragma mark - Class Methods

# pragma mark - Files

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
        NSFileManager *fileManager = [self sharedFileManager];
        if([fileManager fileExistsAtPath:cacheDirectoryPath isDirectory:NULL] == NO) {
            [fileManager createDirectoryAtPath:cacheDirectoryPath withIntermediateDirectories:YES attributes:nil error:NULL];
        }
    });
    return cacheDirectoryPath;
}

+ (NSString *)filePathForKey:(NSString *)key {
    return [[self cacheDirectoryPath] stringByAppendingPathComponent:key];
}

+ (NSOperationQueue *)saveOperationQueue {
    static NSOperationQueue *operationQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        operationQueue = [[NSOperationQueue alloc] init];
        operationQueue.maxConcurrentOperationCount = 1;
    });
    return operationQueue;
}

+ (void)saveImageToDiskForKey:(UIImage *)image key:(NSString *)key {
    [[[self class] saveOperationQueue] addOperationWithBlock:^{
        @try {
            NSString *filePath = [self filePathForKey:key];
            NSData *imageData = UIImagePNGRepresentation(image);
            if(imageData.length < [[self class] freeDiskSpace]) {
                [[self sharedFileManager] createFileAtPath:filePath contents:imageData attributes:nil];
            }
        }
        @catch(NSException *exception) {
#if JGAFImageCache_LOGGING_ENABLED
            NSLog(@"%s [Line %d] %@", __PRETTY_FUNCTION__, __LINE__, exception);
#endif
        }
    }];
}

+ (unsigned long long)freeDiskSpace {
    unsigned long long totalFreeSpace = 0;
    NSError *error = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSDictionary *dictionary = [[[self class] sharedFileManager] attributesOfFileSystemForPath:[paths lastObject] error: &error];
    if (dictionary) {
        NSNumber *freeFileSystemSizeInBytes = [dictionary objectForKey:NSFileSystemFreeSize];
        totalFreeSpace = [freeFileSystemSizeInBytes unsignedLongLongValue];
    }
#if JGAFImageCache_LOGGING_ENABLED
    else if(error) {
        NSLog(@"%s [Line %d] %@", __PRETTY_FUNCTION__, __LINE__, error);
    }
#endif
    return totalFreeSpace;
}

+ (void)removeAllFilesOlderThanDate:(NSDate *)date {
    NSFileManager *fileManager = [self sharedFileManager];
    NSString *cachePath = [self cacheDirectoryPath];
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
#if JGAFImageCache_LOGGING_ENABLED
        if(error != nil) {
            NSLog(@"%s [Line %d] %@", __PRETTY_FUNCTION__, __LINE__, error);
        }
#endif
    }
}

#pragma mark - Internet

+ (NSString *)escapedPathForURL:(NSURL *)url {
    NSString *escapedPath = @"";
    if(url.path.length) {
        escapedPath = [self stringByEscapingSpaces:url.path];
    }
    
    if(url.query.length) {
        escapedPath = [escapedPath stringByAppendingFormat:@"?%@", url.query];
    }
    
    if(url.fragment.length) {
        escapedPath = [escapedPath stringByAppendingFormat:@"#%@", url.fragment];
    }
    
    return escapedPath.length > 0 ? escapedPath : nil;
}

+ (NSString *)stringByEscapingSpaces:(NSString *)string {
    // (<http://www.ietf.org/rfc/rfc3986.txt>)
    CFStringRef escaped =
    CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                            (CFStringRef)string,
                                            NULL,
                                            (CFStringRef)@" ",
                                            kCFStringEncodingUTF8);
    return (__bridge_transfer NSString *)escaped;
}

@end
