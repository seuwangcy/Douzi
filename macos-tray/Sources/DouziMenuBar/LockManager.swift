import Foundation

/// Manages exclusive startup lock to prevent multiple instances from running.
/// Uses flock for atomic lock acquisition and PID file to verify lock holder liveness.
final class LockManager {

    static let shared = LockManager()

    private let lockDir: String
    private let lockFilePath: String
    private let pidFilePath: String
    private var lockFd: Int32 = -1

    private init() {
        lockDir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? "/tmp"
        lockFilePath = lockDir + "/douzi.lock"
        pidFilePath = lockDir + "/douzi.pid"
    }

    /// Attempt to acquire exclusive startup lock.
    /// Returns true on success, false if another instance is running.
    func acquire() -> Bool {
        try? FileManager.default.createDirectory(atPath: lockDir, withIntermediateDirectories: true)

        lockFd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)
        guard lockFd >= 0 else { return false }

        let result = flock(lockFd, LOCK_EX | LOCK_NB)
        if result != 0 {
            close(lockFd)
            lockFd = -1
            return false
        }

        // Write PID so other instances can verify we're alive
        let pid = getpid()
        if let pidData = "\(pid)".data(using: .utf8) {
            try? pidData.write(to: URL(fileURLWithPath: pidFilePath))
        }

        return true
    }

    /// Check if the process holding the lock is still alive.
    func isLockHolderAlive() -> Bool {
        guard let pid = getLockHolderPID() else { return false }
        return kill(pid, 0) == 0
    }

    /// Get the PID of the current lock holder.
    func getLockHolderPID() -> pid_t? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: pidFilePath)),
              let pidStr = String(data: data, encoding: .utf8),
              let pid = pid_t(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
    }

    /// Remove stale lock files.
    func cleanupStaleLock() {
        try? FileManager.default.removeItem(atPath: pidFilePath)
        try? FileManager.default.removeItem(atPath: lockFilePath)
    }

    /// Release the lock. Call when application is terminating.
    func release() {
        guard lockFd >= 0 else { return }
        flock(lockFd, LOCK_UN)
        close(lockFd)
        lockFd = -1
    }

    deinit {
        release()
    }
}