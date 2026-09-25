import Foundation
import AppKit

/// Manages the MiCodexRemote virtual audio driver lifecycle:
/// detection, installation from bundled resources, and removal.
@Observable
public final class DriverManager {
    public enum DriverStatus: Equatable {
        case installed
        case notInstalled
        case installing
        case failed(String)
    }

    public private(set) var status: DriverStatus = .notInstalled

    private static let driverName = "MiCodexRemote2ch.driver"
    private static let halDir = "/Library/Audio/Plug-Ins/HAL"
    public static let installedPath = "\(halDir)/\(driverName)"

    public init() {
        refresh()
    }

    /// Check whether the driver is currently installed.
    public func refresh() {
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.installedPath) {
            status = .installed
        } else {
            status = .notInstalled
        }
    }

    /// Resolve the path to the bundled driver inside the .app bundle or the
    /// project build directory (for development).
    private func bundledDriverPath() -> String? {
        // 1. Inside .app bundle: Contents/Resources/MiCodexRemote2ch.driver
        if let resourcePath = Bundle.main.resourcePath {
            let bundled = (resourcePath as NSString).appendingPathComponent(Self.driverName)
            if FileManager.default.fileExists(atPath: bundled) {
                return bundled
            }
        }

        // 2. Development fallback: ../XiaomiCodexRemoteAudio/MiCodexRemote2ch.driver
        let execURL = Bundle.main.executableURL ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        // Walk up from the executable to find the native/ directory
        var dir = execURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("XiaomiCodexRemoteAudio/\(Self.driverName)").path
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }

        return nil
    }

    /// Install the driver using an AppleScript-prompted admin shell.
    /// This shows the system password dialog to the user.
    public func install(completion: @escaping (Bool, String) -> Void) {
        guard status != .installing else {
            completion(false, "安装正在进行中")
            return
        }

        guard let sourcePath = bundledDriverPath() else {
            status = .failed("未找到驱动文件")
            completion(false, "未找到驱动文件，请先运行 npm run build:audio")
            return
        }

        status = .installing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Build a shell script that copies the driver, sets permissions,
            // and restarts coreaudiod.
            let dest = Self.installedPath
            let script = """
            rm -rf '\(dest)' && \
            cp -R '\(sourcePath)' '\(dest)' && \
            chown -R root:wheel '\(dest)' && \
            find '\(dest)' -type d -exec chmod 755 {} \\; && \
            find '\(dest)' -type f -exec chmod 644 {} \\; && \
            chmod 755 '\(dest)/Contents/MacOS/MiCodexRemote2ch' && \
            killall coreaudiod 2>/dev/null; \
            echo 'DRIVER_INSTALL_OK'
            """

            let (ok, message) = self?.runPrivileged(script: script) ?? (false, "管理器已释放")

            DispatchQueue.main.async {
                if ok {
                    // Wait a moment for coreaudiod to restart and re-enumerate devices
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self?.refresh()
                        completion(true, "驱动安装成功")
                    }
                } else {
                    self?.status = .failed(message)
                    completion(false, message)
                }
            }
        }
    }

    /// Run a shell script with admin privileges via AppleScript `do shell script … with administrator privileges`.
    private func runPrivileged(script: String) -> (Bool, String) {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
                           .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        let osa = NSAppleScript(source: appleScript)
        let result = osa?.executeAndReturnError(&error)

        if let error = error {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "权限验证失败或用户取消"
            return (false, msg)
        }

        let output = result?.stringValue ?? ""
        if output.contains("DRIVER_INSTALL_OK") {
            return (true, "OK")
        }
        return (true, "OK")
    }
}
