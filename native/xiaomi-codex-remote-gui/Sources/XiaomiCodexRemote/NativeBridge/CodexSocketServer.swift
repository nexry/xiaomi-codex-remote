import Foundation
import Darwin

/// All operations and callbacks are serialized on the main queue. Descriptors
/// are nonblocking; slow/disconnected peers must never block the GUI.
final class CodexSocketServer {
    let path: String
    var onFrame: ((Data) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    private var listener: DispatchSourceRead?
    private var reader: DispatchSourceRead?
    private var writer: DispatchSourceWrite?
    private var client: Int32 = -1
    private var input = Data()
    private var output = Data()
    private var ownedIdentity: (dev_t, ino_t)?

    init(path: String) { self.path = path }

    func start() throws {
        dispatchPrecondition(condition: .onQueue(.main))
        guard listener == nil else { return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = path.utf8CString
        guard !path.utf8.contains(0), bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            bytes.withUnsafeBytes { target.copyBytes(from: $0) }
        }
        try removeStaleSocketIfNeeded(address: &address)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError() }
        do {
            try configure(fd)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { throw posixError() }
            var info = stat()
            if lstat(path, &info) == 0 { ownedIdentity = (info.st_dev, info.st_ino) }
            guard chmod(path, 0o600) == 0, Darwin.listen(fd, 4) == 0 else { throw posixError() }
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in self?.acceptClients(fd) }
            source.setCancelHandler { Darwin.close(fd) }
            listener = source
            source.resume()
        } catch {
            Darwin.close(fd)
            removeOwnedSocket()
            throw error
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        disconnect()
        listener?.cancel()
        listener = nil
        removeOwnedSocket()
    }

    func write(_ frame: Data) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard client >= 0 else { return }
        guard frame.count == CodexProtocol.reportSize else {
            onError?("Invalid report size")
            return
        }
        guard output.count < 1024 * 1024 else {
            disconnect()
            onError?("Shim output queue exceeded limit")
            return
        }
        output.append(frame)
        flush()
    }

    private func configure(_ fd: Int32) throws {
        var one: Int32 = 1
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0,
              fcntl(fd, F_SETFD, FD_CLOEXEC) == 0,
              setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one))) == 0
        else { throw posixError() }
    }

    private func removeStaleSocketIfNeeded(address: inout sockaddr_un) throws {
        var original = stat()
        guard lstat(path, &original) == 0,
              original.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK)
        else { return }

        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { throw posixError() }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        let connectError = errno
        Darwin.close(probe)
        guard result != 0, connectError == ECONNREFUSED else { return }

        var current = stat()
        guard lstat(path, &current) == 0,
              current.st_dev == original.st_dev,
              current.st_ino == original.st_ino
        else { return }
        guard Darwin.unlink(path) == 0 else { throw posixError() }
    }

    private func acceptClients(_ fd: Int32) {
        // Bound work per turn so a reconnect storm cannot starve the GUI.
        for _ in 0..<16 {
            let next = Darwin.accept(fd, nil, nil)
            if next < 0 {
                if errno == EINTR { continue }
                if errno != EAGAIN { onError?(posixError().localizedDescription) }
                return
            }
            do { try configure(next) }
            catch { Darwin.close(next); onError?(error.localizedDescription); continue }
            disconnect()
            client = next
            let source = DispatchSource.makeReadSource(fileDescriptor: next, queue: .main)
            source.setEventHandler { [weak self] in
                guard self?.client == next else { return }
                self?.receive()
            }
            source.setCancelHandler { Darwin.close(next) }
            reader = source
            source.resume()
            onConnectionChange?(true)
        }
    }

    private func receive() {
        for _ in 0..<16 {
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(client, &bytes, bytes.count)
            if count > 0 {
                input.append(contentsOf: bytes.prefix(count))
                while input.count >= CodexProtocol.reportSize {
                    let frame = Data(input.prefix(CodexProtocol.reportSize))
                    input.removeFirst(CodexProtocol.reportSize)
                    onFrame?(frame)
                }
            } else if count == 0 { disconnect(); return }
            else if errno == EINTR { continue }
            else if errno == EAGAIN { return }
            else {
                let error = posixError()
                disconnect()
                onError?(error.localizedDescription)
                return
            }
        }
    }

    private func flush() {
        while !output.isEmpty && client >= 0 {
            let count = output.withUnsafeBytes { Darwin.write(client, $0.baseAddress, output.count) }
            if count > 0 { output.removeFirst(count) }
            else if count < 0 && errno == EINTR { continue }
            else if count < 0 && errno == EAGAIN {
                if writer == nil {
                    let source = DispatchSource.makeWriteSource(fileDescriptor: client, queue: .main)
                    source.setEventHandler { [weak self] in self?.flush() }
                    writer = source
                    source.resume()
                }
                return
            } else {
                let error = posixError()
                disconnect()
                onError?(error.localizedDescription)
                return
            }
        }
        writer?.cancel()
        writer = nil
    }

    private func disconnect() {
        guard client >= 0 else { return }
        writer?.cancel()
        writer = nil
        reader?.cancel()
        reader = nil
        client = -1
        input.removeAll()
        output.removeAll()
        onConnectionChange?(false)
    }

    private func removeOwnedSocket() {
        guard let (device, inode) = ownedIdentity else { return }
        var info = stat()
        if lstat(path, &info) == 0, info.st_dev == device, info.st_ino == inode {
            unlink(path)
        }
        ownedIdentity = nil
    }

    private func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    deinit {
        writer?.cancel()
        reader?.cancel()
        listener?.cancel()
        removeOwnedSocket()
    }
}
