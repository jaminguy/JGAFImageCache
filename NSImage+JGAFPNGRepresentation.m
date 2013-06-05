//
//  NSImage+JGAFPNGRepresentation.m
//  Whisper-Mac
//
//  Created by Jamin Guy on 6/4/13.
//  Copyright (c) 2013 Riposte, LLC. All rights reserved.
//

#import "NSImage+JGAFPNGRepresentation.h"

@implementation NSImage (JGAFPNGRepresentation)

- (NSData *)jgaf_pngRepresentation {
    [self lockFocus];
    NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0, 0, self.size.width, self.size.height)];
    [self unlockFocus];
    NSData *data = [bitmapRep representationUsingType:NSPNGFileType properties:nil];
    return data;
}

@end
