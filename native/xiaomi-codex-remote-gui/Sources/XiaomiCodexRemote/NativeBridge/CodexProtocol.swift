import Foundation

enum CodexProtocol {
    static let reportID: UInt8 = 0x06
    static let reportSize = 64
    static let maxPayload = 61
    static let vendorID = 0x303a
    static let productID = 0x8360
    static let usagePage = 0xff00
    static let manufacturer = "Work Louder"
    static let product = "Codex Micro"

    enum Method {
        static let deviceStatus = "device.status"
        static let systemVersion = "sys.version"
        static let lightsPreview = "lights.preview"
        static let rgbConfig = "v.oai.rgbcfg"
        static let threadStatus = "v.oai.thstatus"
    }

    enum Notify {
        static let hid = "v.oai.hid"
        static let joystick = "v.oai.rad"
    }

    enum Action {
        static let release = 0
        static let press = 1
        static let hold = 2
        static let rotate = 2
    }

    enum Key {
        static let agents = ["AG00", "AG01", "AG02", "AG03", "AG04", "AG05"]
        static let actions = ["ACT06", "ACT07", "ACT08", "ACT09", "ACT10", "ACT11", "ACT12"]
        static let encoderCCW = "ENC_CC"
        static let encoderCW = "ENC_CW"
        static let encoderClick = "ENC_CLK"
    }
}

enum CodexChannel: UInt8 {
    case debug = 1
    case rpc = 2
}
