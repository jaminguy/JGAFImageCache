JGAFImageCache (v1.1.1)
==============

A fast reliable image cache for iOS built with AFNetworking.

1. Asynchronously loads from the fastest available source: NSCache, disk, or Internet.
1. Creates SHA1 hash of urls to use as keys.
1. Always calls completion blocks on the main queue.
1. Automatically removes old images in the background.
1. Stays out of your way.

You must include <a href=https://github.com/AFNetworking/AFNetworking>AFNetworking</a> in your project.

`$ git submodule add https://github.com/AFNetworking/AFNetworking.git`

<br>
Version Info:

1.1.1
 - Add CC_LONG cast for 64 bit compatibility.
 - Update cocoapods to use version 1.3.3 of AFNetworking.

1.1.0
 - Add clearAllData method.
 - Remove beta classification.

1.0.2
 - Add serial queue for save to disk operations.
 - Check for available free disk space before saving to disk.

1.0.1
  - Add retry logic.
