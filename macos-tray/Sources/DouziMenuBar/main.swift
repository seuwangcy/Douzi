import Cocoa

// Attempt to acquire exclusive startup lock.
let lockManager = LockManager.shared
if !lockManager.acquire() {
    // Another instance is starting or running - send activate and exit
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("com.douzi.activate"),
        object: nil,
        deliverImmediately: true
    )
    exit(0)
}

// Verify no live Douzi is running by checking port 5000
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

    if connected && !lockManager.isLockHolderAlive() {
        // Stale lock - lock holder is dead, clean up
        lockManager.cleanupStaleLock()
    } else if connected {
        // Another Douzi running
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.douzi.activate"),
            object: nil,
            deliverImmediately: true
        )
        close(fd)
        lockManager.release()
        exit(0)
    }
    close(fd)
}

// No live Douzi running - proceed with startup
AppRunner.shared.run()

// App terminated - release lock
lockManager.release()