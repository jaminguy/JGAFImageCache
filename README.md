JGAFImageCache 2.0.2
==============

A fast reliable image cache for iOS built with NSURLSession.

1. Asynchronously loads from the fastest available source: NSCache, disk, or Internet.
1. Creates SHA1 hash of urls to use as keys.
1. Always calls completion blocks on the main queue.
1. Automatically removes old images in the background.
1. Stays out of your way.

<br>
Version Info:

2.0.2
 - Fix compiler warning because of incorrect class type instantiation.

2.0.1
 - Merge the JGAFSHA1 category into the main source file and remove NSString+JGAFSHA1 files.

2.0.0
 - Remove dependency on AFNetworking in favor of NSURLSession.

1.1.2
 - Fix implicit strong references to self inside blocks.

1.1.1
 - Add CC_LONG cast for 64 bit compatibility.
 - Update podspec to use version 1.3.3 of AFNetworking.

1.1.0
 - Add clearAllData method.
 - Remove beta classification.

1.0.2
 - Add serial queue for save to disk operations.
 - Check for available free disk space before saving to disk.

1.0.1
  - Add retry logic.
