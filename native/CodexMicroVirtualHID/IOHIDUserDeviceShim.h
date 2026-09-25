// Bridging header: exposes the IOHIDUserDevice API to Swift.
//
// The declarations live in <IOKit/hidsystem/IOHIDUserDevice.h>, which ships in
// the macOS SDK and whose symbols are exported by IOKit.framework — but the
// header is deliberately left out of IOKit's Swift module map, so `import IOKit`
// alone can't see it. Importing the header directly here makes
// IOHIDUserDeviceCreateWithProperties and friends available to main.swift.
#import <IOKit/hidsystem/IOHIDUserDevice.h>
