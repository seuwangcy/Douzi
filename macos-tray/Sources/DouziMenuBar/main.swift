import Cocoa

// Singleton pattern: flock + PID file to verify lock holder is alive
// This prevents stale locks (from dead processes) from blocking startup
let lockDir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? "/tmp"
let lockFilePath = lockDir + "/douzi.lock"
let pidFilePath = lockDir + "/douzi.pid"

/// Attempt to acquire exclusive startup lock.
/// Returns file descriptor on success (caller must close), -1 on failure.
/// On success, writes current PID to pidFilePath.
/// On failure (another instance is starting or running), sends activate notification and exits.
func acquireStartupLock() -> Int32 {
    // Ensure lock directory exists
    try? FileManager.default.createDirectory(atPath: lockDir, withIntermediateDirectories: true)

    let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)
    if fd < 0 { return -1 }

    // Try non-blocking exclusive lock
    let result = flock(fd, LOCK_EX | LOCK_NB)
    if result != 0 {
        close(fd)
        return -1
    }

    // Lock acquired - write PID to pidFile so other instances can verify liveness
    let pid = getpid()
    if let pidData = "\(pid)".data(using: .utf8) {
        try? pidData.write(to: URL(fileURLWithPath: pidFilePath))
    }

    return fd
}

/// Check if a process with the given PID is still alive.
/// Returns true if alive, false if dead or PID doesn't exist.
func isProcessAlive(pid: pid_t) -> Bool {
    return kill(pid, 0) == 0
}

/// Find the PID of the process currently holding the startup lock.
/// Returns nil if pidFile doesn't exist or is invalid.
func getLockHolderPID() -> pid_t? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: pidFilePath)),
          let pidStr = String(data: data, encoding: .utf8),
          let pid = pid_t(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return nil
    }
    return pid
}

/// Send activate notification to bring existing instance to foreground.
func sendActivateNotification() {
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("com.douzi.activate"),
        object: nil,
        deliverImmediately: true
    )
}

/// Remove stale lock files (pid file and lock file).
func cleanupStaleLock() {
    try? FileManager.default.removeItem(atPath: pidFilePath)
    try? FileManager.default.removeItem(atPath: lockFilePath)
}

let lockFd = acquireStartupLock()
if lockFd < 0 {
    // Another instance is starting or running
    sendActivateNotification()
    exit(0)
}

// At this point we hold the exclusive lock.
// Verify no other instance is already running by checking port 5000.
var addr = sockaddr_in()
addr.sin_len = UInt8(MemoryLayout.size(ofValue: addr))
addr.sin_family = sa_family_t(AF_INET)
addr.sin_port = CFSwapInt16HostToBig(UInt16(5000))
addr.sin_addr.s_addr = inet_addr("127.0.0.1")

let fd = socket(AF_INET, SOCK_STREAM, 0)
var existingPID: pid_t = 0
if fd >= 0 {
    let connected = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
            Darwin.connect(fd, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    } == 0
    if connected {
        // Something is listening on port 5000 - check if it's a live Douzi process
        existingPID = getLockHolderPID() ?? 0
        if existingPID != 0 && !isProcessAlive(pid: existingPID) {
            // Stale lock - the process holding the lock is dead but lock wasn't cleaned up
            // This can happen if the process was killed without proper cleanup
            existingPID = 0
            cleanupStaleLock()
        }
    }
    close(fd)
}

if existingPID != 0 {
    // Another Douzi instance is running - send activate and exit
    flock(lockFd, LOCK_UN)
    close(lockFd)
    sendActivateNotification()
    exit(0)
}

// No live Douzi running - we are the primary instance
// Keep lock held for the lifetime of the app; it will be released on exit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

flock(lockFd, LOCK_UN)
close(lockFd)
