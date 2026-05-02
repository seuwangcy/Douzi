import Cocoa

// Attempt to acquire exclusive startup lock.
// LockManager automatically cleans up stale locks on startup.
let lockManager = LockManager.shared

if !lockManager.acquire() {
    // Another instance is running - bring it to front and exit
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("com.douzi.activate"),
        object: nil,
        deliverImmediately: true
    )
    exit(0)
}

// Also check port 5000 to handle edge case where lock file survived but process died
var addr = sockaddr_in()
addr.sin_len = UInt8(MemoryLayout.size(ofValue: addr))
addr.sin_family = sa_family_t(AF_INET)
addr.sin_port = CFSwapInt16HostToBig(UInt16(5000))
addr.sin_addr.s_addr = inet_addr("127.0.0.1")

let fd = socket(AF_INET, SOCK_STREAM, 0)
if fd >= 0 {
    let connected = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
            Darwin.connect(fd, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    } == 0

    if connected {
        // Something on port 5000 - if it's not our lock holder, activate and exit
        if !lockManager.isLockHolderAlive {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.douzi.activate"),
                object: nil,
                deliverImmediately: true
            )
            close(fd)
            lockManager.release()
            exit(0)
        }
    }
    close(fd)
}

// No live Douzi running - proceed with startup
AppRunner.shared.run()

// App terminated - lock will be released via atexit handler