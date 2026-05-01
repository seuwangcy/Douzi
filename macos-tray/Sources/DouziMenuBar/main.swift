import Cocoa

// Prevent race condition during startup: two processes might both pass port check
// before either starts the server. Use flock for a brief exclusive window.
let lockFilePath = (NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? "/tmp") + "/douzi.lock"

func acquireStartupLock() -> Int32 {
    let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)
    if fd < 0 { return -1 }
    let result = flock(fd, LOCK_EX | LOCK_NB)
    if result != 0 {
        close(fd)
        return -1
    }
    return fd
}

let lockFd = acquireStartupLock()
if lockFd < 0 {
    // Another instance is starting or running
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("com.douzi.activate"),
        object: nil,
        deliverImmediately: true
    )
    exit(0)
}

// Singleton check via port 5000
var addr = sockaddr_in()
addr.sin_len = UInt8(MemoryLayout.size(ofValue: addr))
addr.sin_family = sa_family_t(AF_INET)
addr.sin_port = CFSwapInt16HostToBig(UInt16(5000))
addr.sin_addr.s_addr = inet_addr("127.0.0.1")

let fd = socket(AF_INET, SOCK_STREAM, 0)
var alreadyRunning = false
if fd >= 0 {
    alreadyRunning = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
            Darwin.connect(fd, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    } == 0
    close(fd)
}

if alreadyRunning {
    flock(lockFd, LOCK_UN)
    close(lockFd)
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("com.douzi.activate"),
        object: nil,
        deliverImmediately: true
    )
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

flock(lockFd, LOCK_UN)
close(lockFd)
