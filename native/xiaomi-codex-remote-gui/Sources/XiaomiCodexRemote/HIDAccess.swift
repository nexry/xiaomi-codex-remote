import IOKit.hid

enum HIDAccessStatus: Equatable { case granted, denied, unknown }
protocol HIDAccessProviding {
    var status: HIDAccessStatus { get }
    @discardableResult func request() -> Bool
}
struct SystemHIDAccessProvider: HIDAccessProviding {
    var status: HIDAccessStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .unknown
        }
    }
    func request() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
}
enum HIDMonitorStatus: Equatable {
    case stopped, permissionRequired, permissionDenied, searching
    case connected(name: String), failed(String)
}
