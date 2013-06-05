//
//  NSImage+JGAFPNGRepresentation.h
//  Whisper-Mac
//
//  Created by Jamin Guy on 6/4/13.
//  Copyright (c) 2013 Riposte, LLC. All rights reserved.
//
#if defined(__MAC_OS_X_VERSION_MIN_REQUIRED)
#import <Cocoa/Cocoa.h>

@interface NSImage (JGAFPNGRepresentation)

- (NSData *)jgaf_pngRepresentation;

@end
#endif
