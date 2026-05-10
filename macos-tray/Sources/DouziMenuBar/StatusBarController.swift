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
    private var lightIcon: NSImage?
    private var darkIcon: NSImage?
    private var appearanceObservation: NSKeyValueObservation?

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

        loadIcons()
    }

    private func loadIcons() {
        // Light mode icon (dark fill on transparent)
        if let path = Bundle.module.path(forResource: "AppIcon_menubar", ofType: "png") {
            lightIcon = NSImage(contentsOfFile: path)
        }
        // Dark mode icon (white fill on transparent)
        if let path = Bundle.module.path(forResource: "AppIcon_menubar_dark", ofType: "png") {
            darkIcon = NSImage(contentsOfFile: path)
        }
    }

    /// Determine the correct icon based on the status bar button's actual appearance.
    /// In fullscreen mode, macOS forces the menu bar to dark regardless of system theme,
    /// so we must check the button's own effectiveAppearance instead of the app-level one.
    private var currentIcon: NSImage? {
        let appearance = statusItem?.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        let isDarkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDarkMode ? darkIcon : lightIcon
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem.button else {
            return
        }

        btn.image = currentIcon ?? fallbackIcon
        btn.imageScaling = .scaleProportionallyDown
        btn.imagePosition = .imageOnly

        buildMenu()

        // Use KVO on the status bar button's effectiveAppearance.
        // This correctly detects fullscreen mode changes where macOS forces
        // a dark menu bar, as well as normal system theme switches.
        appearanceObservation = btn.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateIcon()
            }
        }
    }

    private func updateIcon() {
        statusItem.button?.image = currentIcon ?? fallbackIcon
    }

    private var fallbackIcon: NSImage? {
        if #available(macOS 11.0, *) {
            return NSImage(systemSymbolName: "circle.circle.fill",
                           accessibilityDescription: "Douzi")
        } else {
            return nil
        }
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