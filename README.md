JGAFImageCache (v0.1 Alpha: use at your own risk)
==============


A fast reliable image cache for iOS built with AFNetworking.
<br>
 1. Asynchronously loads from the fastest available source: NSCache, disk, or internet
 2. Creates SHA1 hash of the url to use as the key
 3. Always calls completion blocks on the main queue
 4. Automatically removes old images in the background
 5. Stays out of your way
 
You must include <a href=https://github.com/AFNetworking/AFNetworking>AFNetworking</a> in your project.

git submodule add https://github.com/AFNetworking/AFNetworking.git

<br>

License
===
Copyright (c) 2013 Jamin Guy

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.