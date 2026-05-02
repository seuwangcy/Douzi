import Cocoa

/// Thin application delegate that coordinates between components.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!
    private var quickAddWindowController: QuickAddWindowController!
    private var statusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        quickAddWindowController = QuickAddWindowController()

        statusBarController = StatusBarController(
            onQuickAdd: { [weak self] in self?.openQuickAdd() },
            onOpenWeb: { [weak self] in self?.openWebApp() },
            onOrganize: { [weak self] in self?.organizeInbox() },
            onRestartServer: { ServerManager.shared.restart() },
            onStopServer: { ServerManager.shared.stop() },
            onQuit: { [weak self] in self?.quitApp() }
        )
        statusBarController.setup()

        ServerManager.shared.onStatusChanged = { [weak self] isRunning in
            DispatchQueue.main.async {
                self?.statusBarController.updateServiceStatus(isRunning: isRunning)
            }
        }

        if !ServerManager.shared.checkStatus() {
            ServerManager.shared.start()
        }

        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            let _ = ServerManager.shared.checkStatus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
        ServerManager.shared.stop()
    }

    // MARK: - Actions

    private func openQuickAdd() {
        quickAddWindowController.onSubmit = { [weak self] text in
            self?.submitQuickAdd(text: text)
        }
        quickAddWindowController.show()
    }

    private func submitQuickAdd(text: String) {
        guard !text.isEmpty else { return }
        ServerManager.shared.submitQuickAdd(text: text) { err in
            if let err = err {
                UIHelper.showAlert(title: "添加失败", message: err.localizedDescription)
            } else {
                UIHelper.showToast("✅ 已添加到 Inbox")
            }
        }
    }

    private func openWebApp() {
        if !ServerManager.shared.running {
            ServerManager.shared.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSWorkspace.shared.open(ServerManager.shared.webURL)
            }
        } else {
            NSWorkspace.shared.open(ServerManager.shared.webURL)
        }
    }

    private func organizeInbox() {
        ServerManager.shared.organizeInbox { result in
            if let result = result {
                UIHelper.showAlert(title: "✨ 整理完成", message: result)
            } else {
                UIHelper.showToast("整理请求已发送 ✅")
            }
        }
    }

    private func quitApp() {
        ServerManager.shared.stop()
        NSApp.terminate(nil)
    }
}