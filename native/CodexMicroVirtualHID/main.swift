// CodexMicroVirtualHID — a thin native bridge that creates a virtual USB HID
// device matching the Codex Micro's identity (VID 0x303A / PID 0x8360 / vendor
// usage page 0xFF00) and pumps raw 64-byte HID reports between it and a Unix
// domain socket. All protocol logic lives in the Node process on the other end
// of the socket; this helper is deliberately dumb.
//
//   ChatGPT app ──USB──▶ IOHIDUserDevice ──(SetReport)──▶ socket ──▶ Node
//   Node ──▶ socket ──(HandleReport)──▶ IOHIDUserDevice ──USB──▶ ChatGPT app
//
// Build:  ./build.sh      Run:  sudo ./CodexMicroVirtualHID /tmp/codex-micro-vhid.sock
//
// Uses only public-SDK symbols (IOHIDUserDeviceCreateWithProperties + the
// block/dispatch-queue API), surfaced to Swift via IOHIDUserDeviceShim.h.
//
// NOTE: On recent macOS, creating an IOHIDUserDevice typically requires running
// as root and may require the `com.apple.developer.hid.virtual.device`
// entitlement on a signed binary. If creation fails, this tool prints guidance.

import Foundation
import IOKit
import IOKit.hid

let REPORT_SIZE = 64 // report ID + 63 data bytes
let REPORT_ID: UInt8 = 0x06

// HID report descriptor: one vendor-defined (0xFF00) application collection,
// report ID 6, 63-byte input + 63-byte output. Must match src/protocol.js.
let reportDescriptor: [UInt8] = [
    0x06, 0x00, 0xFF, // Usage Page (Vendor 0xFF00)
    0x09, 0x01,       // Usage (0x01)
    0xA1, 0x01,       // Collection (Application)
    0x85, 0x06,       //   Report ID (6)
    0x09, 0x01,       //   Usage (0x01)
    0x15, 0x00,       //   Logical Minimum (0)
    0x26, 0xFF, 0x00, //   Logical Maximum (255)
    0x75, 0x08,       //   Report Size (8)
    0x95, 0x3F,       //   Report Count (63)
    0x81, 0x02,       //   Input (Data,Var,Abs)
    0x09, 0x01,       //   Usage (0x01)
    0x91, 0x02,       //   Output (Data,Var,Abs)
    0xC0,             // End Collection
]

func stderrLine(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

// Shared state reachable from the SetReport block and the socket threads.
final class Bridge {
    var device: IOHIDUserDevice?
    var clientFD: Int32 = -1
    let lock = NSLock()

    // Forward a host→device OUT report to the socket as a fixed 64-byte frame:
    // [reportID, ...reportBytes].
    func forwardToSocket(reportID: UInt32, bytes: UnsafePointer<UInt8>, length: Int) {
        var frame = [UInt8](repeating: 0, count: REPORT_SIZE)
        frame[0] = reportID == 0 ? REPORT_ID : UInt8(reportID & 0xFF)
        let n = min(length, REPORT_SIZE - 1)
        for i in 0..<n { frame[i + 1] = bytes[i] }

        lock.lock()
        let fd = clientFD
        lock.unlock()
        guard fd >= 0 else { return }
        frame.withUnsafeBytes { _ = write(fd, $0.baseAddress, REPORT_SIZE) }
    }

    // Inject a device→host INPUT report received from the socket.
    func injectInput(frame: [UInt8]) {
        guard let device = device else { return }
        let buf = frame
        let result = buf.withUnsafeBufferPointer { ptr -> IOReturn in
            IOHIDUserDeviceHandleReportWithTimeStamp(device, mach_absolute_time(),
                                                     ptr.baseAddress!, ptr.count)
        }
        if result != kIOReturnSuccess {
            stderrLine("HandleReport failed: \(String(format: "0x%08x", result))")
        }
    }
}

let bridge = Bridge()

func makeProperties() -> CFDictionary {
    let props: [String: Any] = [
        "ReportDescriptor": Data(reportDescriptor),
        "VendorID": 0x303A,
        "ProductID": 0x8360,
        "VersionNumber": 0x0100,
        "Manufacturer": "Work Louder",
        "Product": "Codex Micro",
        "PrimaryUsagePage": 0xFF00,
        "PrimaryUsage": 0x01,
        "Transport": "USB",
    ]
    return props as CFDictionary
}

// ---- Unix socket server ---------------------------------------------------

func startSocketServer(path: String) {
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { perror("socket"); exit(1) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    _ = path.withCString { cstr in
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: 104) { strncpy($0, cstr, 103) }
        }
    }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
    }
    guard bound == 0 else { perror("bind"); exit(1) }
    guard listen(fd, 1) == 0 else { perror("listen"); exit(1) }
    stderrLine("Listening on \(path)")

    DispatchQueue.global().async {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { continue }
            bridge.lock.lock(); bridge.clientFD = client; bridge.lock.unlock()
            stderrLine("Bridge connected.")
            readLoop(client)
            bridge.lock.lock(); bridge.clientFD = -1; bridge.lock.unlock()
            close(client)
            stderrLine("Bridge disconnected.")
        }
    }
}

// Read fixed 64-byte frames from the client and inject them as input reports.
func readLoop(_ client: Int32) {
    var acc = [UInt8]()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = chunk.withUnsafeMutableBytes { read(client, $0.baseAddress, 4096) }
        if n <= 0 { break }
        acc.append(contentsOf: chunk[0..<n])
        while acc.count >= REPORT_SIZE {
            let frame = Array(acc[0..<REPORT_SIZE])
            acc.removeFirst(REPORT_SIZE)
            bridge.injectInput(frame: frame)
        }
    }
}

// ---- main -----------------------------------------------------------------

let socketPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : NSTemporaryDirectory() + "codex-micro-vhid.sock"

guard let device = IOHIDUserDeviceCreateWithProperties(kCFAllocatorDefault, makeProperties(), 0) else {
    stderrLine("""
    Failed to create the virtual HID device (IOHIDUserDeviceCreateWithProperties returned nil).

    Most likely causes:
      • Not running as root — try:  sudo ./CodexMicroVirtualHID \(socketPath)
      • macOS requires the com.apple.developer.hid.virtual.device entitlement on
        a signed binary. Request it from Apple, then codesign this helper with it.

    See the README ("macOS virtual-HID caveats") for the full walkthrough.
    """)
    exit(2)
}
bridge.device = device

// Handle host→device reports on a dedicated queue.
let hidQueue = DispatchQueue(label: "codex-micro.vhid")
let setReportBlock: IOHIDUserDeviceSetReportBlock = { (type, reportID, report, reportLength) -> IOReturn in
    bridge.forwardToSocket(reportID: reportID, bytes: report, length: reportLength)
    return kIOReturnSuccess
}
IOHIDUserDeviceRegisterSetReportBlock(device, setReportBlock)
IOHIDUserDeviceSetDispatchQueue(device, hidQueue)
IOHIDUserDeviceActivate(device)

stderrLine("Virtual Codex Micro created (VID 0x303A / PID 0x8360). ChatGPT should now detect it.")

startSocketServer(path: socketPath)
CFRunLoopRun()
