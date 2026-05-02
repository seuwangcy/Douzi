import Cocoa

/// Coordinates application startup and lifecycle.
final class AppRunner {

    static let shared = AppRunner()

    private let delegate: AppDelegate

    private init() {
        delegate = AppDelegate()
    }

    /// Run the application. This blocks until the app terminates.
    func run() {
        NSApp.delegate = delegate
        NSApp.run()
    }
}