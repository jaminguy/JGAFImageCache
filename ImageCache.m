//
//  ImageCache.m
//  ImageCache
//
//  Created by Paresh Navadiya on 16/03/2016.
//  Copyright (c) 2013 Paresh Navadiya. All rights reserved.
//

#import "ImageCache.h"

#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

#pragma mark - NSOperation for NSURLSession

@interface NSURLSessionOperation : NSOperation

- (instancetype)initWithSession:(NSURLSession *)session URL:(NSURL *)url completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;
- (instancetype)initWithSession:(NSURLSession *)session request:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;

@property (nonatomic, strong, readonly) NSURLSessionDataTask *task;

@end

#define KVOBlock(KEYPATH, BLOCK) \
[self willChangeValueForKey:KEYPATH]; \
BLOCK(); \
[self didChangeValueForKey:KEYPATH];

@implementation NSURLSessionOperation {
    BOOL _finished;
    BOOL _executing;
}

- (instancetype)initWithSession:(NSURLSession *)session URL:(NSURL *)url completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    if (self = [super init]) {
        __weak typeof(self) weakSelf = self;
        _task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(data, response, error);
                [weakSelf completeOperation];

            });
        }];
    }
    return self;
}

- (instancetype)initWithSession:(NSURLSession *)session request:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    if (self = [super init]) {
        __weak typeof(self) weakSelf = self;
        _task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(data, response, error);
                [weakSelf completeOperation];

            });
        }];
    }
    return self;
}

- (void)cancel {
    [super cancel];
    [self.task cancel];
}

- (void)start {
    if (self.isCancelled) {
        KVOBlock(@"isFinished", ^{ _finished = YES; });
        return;
    }
    KVOBlock(@"isExecuting", ^{
        [self.task resume];
        _executing = YES;
    });
}

- (BOOL)isExecuting {
    return _executing;
}

- (BOOL)isFinished {
    return _finished;
}

- (BOOL)isConcurrent {
    return YES;
}

- (void)completeOperation {
    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    
    _executing = NO;
    _finished = YES;
    
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

@end

#pragma mark - NSString (JGAFSHA1)

@interface NSString (JGAFSHA1)

- (NSString*)jgaf_sha1;

@end

@implementation NSString (JGAFSHA1)

/* See here for more info: Getting MD5 and SHA-1 http://stackoverflow.com/a/6006747/648774 */

- (NSString *)jgaf_sha1 {
    NSMutableString *mutableSHA1 = nil;
    NSData *data = [self dataUsingEncoding: NSUTF8StringEncoding]; /* A different encoding can be used here. */
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    if(CC_SHA1(data.bytes, (CC_LONG)data.length, digest)) {
        mutableSHA1 = [[NSMutableString alloc] initWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
        for(int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
            [mutableSHA1 appendFormat:@"%02x", digest[i]];
        }
    }
    return mutableSHA1;
}

@end


#pragma mark - ImageCache

@interface ImageCache ()

@property (strong, nonatomic) NSCache *imageCache;
@property (strong, nonatomic) NSURLSession *urlSession;
@property (strong, nonatomic) NSOperationQueue *operationQueue;

@end

@implementation ImageCache

+ (ImageCache *)sharedInstance {
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
        _fileExpirationInterval = ImageCache_DEFAULT_EXPIRATION_INTERVAL;
        _imageCache = [[NSCache alloc] init];
        _maxNumberOfRetries = 0;
        _retryDelay = 0.0;
        
        NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:sessionConfiguration];
        _urlSession = urlSession;
        
        NSOperationQueue *operationQueue = [[NSOperationQueue alloc] init];
        _operationQueue = operationQueue;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        __weak ImageCache *weakSelf = self;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            [weakSelf.imageCache removeAllObjects];
        }];
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
        __weak ImageCache *weakSelf = self;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSDate *maxAge = [NSDate dateWithTimeIntervalSinceNow:weakSelf.fileExpirationInterval];
            [[self class] removeAllFilesOlderThanDate:maxAge];
            [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
        });
    }
}

- (void)imageForURL:(NSString *)url completion:(void (^)(UIImage *image))completion {
    NSAssert(url.length > 0, @"url cannot be nil");
    __weak ImageCache *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *sha1 = [url jgaf_sha1];
        UIImage *image = [weakSelf.imageCache objectForKey:sha1];
        if(image == nil) {
            image = [weakSelf imageFromDiskForKey:sha1];
        }
        

        if(image == nil) {
            
            NSArray<NSURLSessionOperation *> *allCurOperations = self.operationQueue.operations.copy;
            
            NSURLSessionOperation *operationWithRequest = nil;
            for (NSURLSessionOperation *operation in allCurOperations) {
                
                NSString *strRequestURL = [operation.task.originalRequest.URL absoluteString];
                NSString *strCurRequestURL = [operation.task.currentRequest.URL absoluteString];
                if ([strRequestURL isEqualToString:url] || [strCurRequestURL isEqualToString:url]) {
                    operationWithRequest = operation;
                    break;
                }
                
            }
            
            if (!operationWithRequest)
                [weakSelf loadRemoteImageForURL:url key:sha1 retryCount:0 completion:completion];
            else
                [operationWithRequest start];
                
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
            // Update the file modification date for use by the removeAllFilesOlderThanDate: method
            [fileManager setAttributes:@{NSFileModificationDate:[NSDate date]} ofItemAtPath:filePath error:NULL];
            image = [[self class] imageWithData:[fileManager contentsAtPath:filePath]];
            if (image) {
                [_imageCache setObject:image forKey:key];
            }
        }
    }
    @catch(NSException *exception) {
#if ImageCache_LOGGING_ENABLED
        NSLog(@"%s [Line %d] %@", __PRETTY_FUNCTION__, __LINE__, exception);
#endif
    }
    return image;
}

- (void)loadRemoteImageForURL:(NSString *)url key:(NSString *)key retryCount:(NSInteger)retryCount completion:(void (^)(UIImage *image))completion {
    //NSLog(@"%@",url);
    if (url.length > 0) {
        NSURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
        __weak ImageCache *weakSelf = self;
        
        NSURLSessionOperation *imgDownloadOperation = [[NSURLSessionOperation alloc] initWithSession:weakSelf.urlSession request:urlRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            
            if (error == nil) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                NSInteger httpStatusCode = httpResponse.statusCode;
                switch (httpStatusCode) {
                    case 200: {
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                            UIImage *image = nil;
                            if(data.length) {
                                @try {
                                    image = [[weakSelf class] imageWithData:data];
                                }
                                @catch(NSException *exception) {
#if ImageCache_LOGGING_ENABLED
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
                            
#if ImageCache_LOGGING_ENABLED
                            NSLog(@"%s [Line %d] retrying(%d)", __PRETTY_FUNCTION__, __LINE__, (int)nextRetryCount);
#endif
                        }
                        
#if ImageCache_LOGGING_ENABLED
                        NSLog(@"%s [Line %d] statusCode(%d) %@", __PRETTY_FUNCTION__, __LINE__, (int)httpStatusCode, response);
#endif
                    } break;
                }
            }
            else {
#if ImageCache_LOGGING_ENABLED
                NSLog(@"%s [Line %d] %@", __PRETTY_FUNCTION__, __LINE__, error);
#endif
            }

        }];
        //firstly add operations
        [self.operationQueue addOperation:imgDownloadOperation];
        [imgDownloadOperation start];
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

#pragma mark - Images

+ (UIImage *)imageWithData:(NSData *)data {
    @synchronized(self) {
        return [[UIImage alloc] initWithData:data];
    }
}

#pragma mark - Files

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
        cacheDirectoryPath = [[[caches objectAtIndex:0] stringByAppendingPathComponent:@"ImageCache"] copy];
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
#if ImageCache_LOGGING_ENABLED
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
#if ImageCache_LOGGING_ENABLED
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
#if ImageCache_LOGGING_ENABLED
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
