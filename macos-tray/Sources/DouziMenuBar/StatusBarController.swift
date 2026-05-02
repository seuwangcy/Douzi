import Cocoa

/// Manages the macOS status bar (menu bar) item.
final class StatusBarController {

    private var statusItem: NSStatusItem!
    private let onQuickAdd: () -> Void
    private let onOpenWeb: () -> Void
    private let onOrganize: () -> Void
    private let onRestartServer: () -> Void
    private let onStopServer: () -> Void
    private let onQuit: () -> Void

    private var serviceStatusItem: NSMenuItem?

    init(
        onQuickAdd: @escaping () -> Void,
        onOpenWeb: @escaping () -> Void,
        onOrganize: @escaping () -> Void,
        onRestartServer: @escaping () -> Void,
        onStopServer: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onQuickAdd = onQuickAdd
        self.onOpenWeb = onOpenWeb
        self.onOrganize = onOrganize
        self.onRestartServer = onRestartServer
        self.onStopServer = onStopServer
        self.onQuit = onQuit
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem.button else {
            return
        }

        // Load custom icon from bundle
        if let imgPath = Bundle.module.path(forResource: "AppIcon_menubar", ofType: "png"),
           let image = NSImage(contentsOfFile: imgPath) {
            btn.image = image
        } else if #available(macOS 11.0, *) {
            btn.image = NSImage(systemSymbolName: "circle.circle.fill",
                                accessibilityDescription: "Douzi")
            btn.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        } else {
            btn.title = "⦿"
        }

        btn.imageScaling = .scaleProportionallyDown
        btn.imagePosition = .imageOnly

        buildMenu()
    }

    func updateServiceStatus(isRunning: Bool) {
        serviceStatusItem?.title = isRunning ? "✅ 服务运行中 (5000)" : "⏹️ 服务已停止"
    }

    private func buildMenu() {
        let menu = NSMenu()

        let quickAddItem = NSMenuItem(title: "✨ 快速添加待办", action: #selector(handleQuickAdd), keyEquivalent: "n")
        quickAddItem.target = self
        menu.addItem(quickAddItem)

        let openWebItem = NSMenuItem(title: "🌐 打开看板", action: #selector(handleOpenWeb), keyEquivalent: "o")
        openWebItem.target = self
        menu.addItem(openWebItem)

        let organizeItem = NSMenuItem(title: "🧠 一键整理 Inbox", action: #selector(handleOrganize), keyEquivalent: "")
        organizeItem.target = self
        menu.addItem(organizeItem)

        menu.addItem(NSMenuItem.separator())

        serviceStatusItem = NSMenuItem(title: "⏹️ 服务已停止", action: nil, keyEquivalent: "")
        serviceStatusItem?.isEnabled = false
        serviceStatusItem?.tag = 100
        menu.addItem(serviceStatusItem!)

        menu.addItem(NSMenuItem.separator())

        let restartItem = NSMenuItem(title: "🔄 重启服务", action: #selector(handleRestartServer), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let stopItem = NSMenuItem(title: "🛑 停止服务", action: #selector(handleStopServer), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 Douzi", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func handleQuickAdd() { onQuickAdd() }
    @objc private func handleOpenWeb() { onOpenWeb() }
    @objc private func handleOrganize() { onOrganize() }
    @objc private func handleRestartServer() { onRestartServer() }
    @objc private func handleStopServer() { onStopServer() }
    @objc private func handleQuit() { onQuit() }
}