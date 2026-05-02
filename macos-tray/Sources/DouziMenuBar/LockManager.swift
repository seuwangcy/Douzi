import Foundation

/// Manages exclusive startup lock to prevent multiple instances from running.
/// Uses flock for atomic lock acquisition and PID file to verify lock holder liveness.
/// Automatically cleans up stale locks on startup.
final class LockManager {

    static let shared = LockManager()

    private let lockDir: String
    private let lockFilePath: String
    private let pidFilePath: String
    private var lockFd: Int32 = -1
    private var isRegistered = false

    private init() {
        lockDir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? "/tmp"
        lockFilePath = lockDir + "/douzi.lock"
        pidFilePath = lockDir + "/douzi.pid"
    }

    /// Attempt to acquire exclusive startup lock.
    /// If another instance is running, sends activate notification and returns false.
    /// If stale lock detected (lock holder dead), automatically cleans up and retries.
    /// Returns true on success, false if another instance is running.
    @discardableResult
    func acquire() -> Bool {
        // Ensure lock directory exists
        try? FileManager.default.createDirectory(atPath: lockDir, withIntermediateDirectories: true)

        // First, check if there's an existing lock and if it's stale
        cleanupStaleLockIfNeeded()

        // Try to acquire lock
        lockFd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)
        guard lockFd >= 0 else { return false }

        let result = flock(lockFd, LOCK_EX | LOCK_NB)
        if result != 0 {
            // Lock is held by another process
            close(lockFd)
            lockFd = -1
            return false
        }

        // Lock acquired - write PID
        let pid = getpid()
        if let pidData = "\(pid)".data(using: .utf8) {
            try? pidData.write(to: URL(fileURLWithPath: pidFilePath))
        }

        // Register cleanup handlers for any exit scenario
        registerCleanupHandlers()

        return true
    }

    /// Check if process holding the lock is still alive.
    var isLockHolderAlive: Bool {
        guard let pid = getLockHolderPID() else { return false }
        return kill(pid, 0) == 0
    }

    /// Get PID of current lock holder.
    private func getLockHolderPID() -> pid_t? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: pidFilePath)),
              let pidStr = String(data: data, encoding: .utf8),
              let pid = pid_t(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
    }

    /// Clean up stale lock if the holder is dead.
    private func cleanupStaleLockIfNeeded() {
        guard FileManager.default.fileExists(atPath: lockFilePath) else { return }

        // Check if lock file is locked by another process
        let testFd = open(lockFilePath, O_RDWR, 0o644)
        guard testFd >= 0 else { return }
        defer { close(testFd) }

        // Try non-blocking shared lock to check if exclusive lock is held
        let result = flock(testFd, LOCK_EX | LOCK_NB)
        if result == 0 {
            // No one holds the exclusive lock, but file exists - clean it up
            flock(testFd, LOCK_UN)
            cleanupStaleLock()
            return
        }

        // Exclusive lock is held - check if holder is alive
        if let pid = getLockHolderPID(), kill(pid, 0) != 0 {
            // Lock holder is dead, clean up
            cleanupStaleLock()
        }
    }

    /// Remove stale lock files.
    func cleanupStaleLock() {
        try? FileManager.default.removeItem(atPath: pidFilePath)
        try? FileManager.default.removeItem(atPath: lockFilePath)
    }

    /// Release the lock. Called automatically on exit.
    func release() {
        guard lockFd >= 0 else { return }
        flock(lockFd, LOCK_UN)
        close(lockFd)
        lockFd = -1
        try? FileManager.default.removeItem(atPath: pidFilePath)
        try? FileManager.default.removeItem(atPath: lockFilePath)
    }

    /// Register cleanup handlers for all exit scenarios.
    private func registerCleanupHandlers() {
        guard !isRegistered else { return }
        isRegistered = true

        // atexit handles normal termination
        atexit {
            LockManager.shared.release()
        }

        // Signal handlers for abnormal termination
        signal(SIGTERM) { _ in
            LockManager.shared.release()
            exit(0)
        }
        signal(SIGINT) { _ in
            LockManager.shared.release()
            exit(0)
        }
        signal(SIGHUP) { _ in
            LockManager.shared.release()
            exit(0)
        }
    }
}