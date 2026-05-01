import Cocoa
import Foundation
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var serverProcess: Process?
    private var statusTimer: Timer?
    private let baseDir: String
    private let projectDir: String
    private let logPath: String
    private var isRunning = false
    private let serverURL = URL(string: "http://127.0.0.1:5000/api/quick-add")!
    private let webURL = URL(string: "http://127.0.0.1:5000")!

    private var quickAddWindow: NSWindow?

    override init() {
        let fm = FileManager.default
        // 从可执行文件所在目录推导 Douzi 项目根目录
        // 可执行文件位于 ~/.douzi/macos-tray/.build/debug/DouziMenuBar
        // 或 ~/Applications/Douzi.app/Contents/MacOS/DouziLauncher
        let execPath = Bundle.main.executablePath ?? ""
        let execURL = URL(fileURLWithPath: execPath)
        let execDir = execURL.deletingLastPathComponent().path

        var projectDirCandidate: String
        if execDir.hasSuffix("/Contents/MacOS") {
            // Launchpad 启动: DouziLauncher 脚本
            let homeDir = NSHomeDirectory()
            projectDirCandidate = homeDir + "/.douzi"
        } else {
            // 直接运行: DouziMenuBar 二进制，或通过 DouziLauncher -> exec 间接运行
            // execPath 可能是 ~/.douzi/macos-tray/.build/debug/DouziMenuBar
            // 也可能是 ~/Applications/Douzi.app/.../DouziLauncher（但实际应该是前者）
            let macosTrayDir = (execDir as NSString).deletingLastPathComponent // .build/debug -> .build
            let buildDir = (macosTrayDir as NSString).deletingLastPathComponent // .build -> macos-tray
            let parentDir = (buildDir as NSString).deletingLastPathComponent // macos-tray -> ~/.douzi

            if fm.fileExists(atPath: parentDir + "/server.mjs") {
                projectDirCandidate = parentDir
            } else {
                // Fallback: 相对路径推导（用于某些间接调用场景）
                let step1 = (execDir as NSString).deletingLastPathComponent
                let step2 = (step1 as NSString).deletingLastPathComponent
                let step3 = (step2 as NSString).deletingLastPathComponent
                let step4 = (step3 as NSString).deletingLastPathComponent
                projectDirCandidate = step4
            }
        }

        if fm.fileExists(atPath: projectDirCandidate + "/server.mjs") {
            self.projectDir = projectDirCandidate
        } else {
            // 回退到当前工作目录
            self.projectDir = fm.currentDirectoryPath
        }
        self.baseDir = self.projectDir + "/knowledge-base/gtd"
        self.logPath = self.projectDir + "/.douzi-server.log"
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem.button else {
            showAlert(title: "Douzi", message: "状态栏空间不足，无法显示图标。")
            NSApp.terminate(nil)
            return
        }

        // 用系统 SF Symbols — 最稳定
        if #available(macOS 11.0, *) {
            btn.image = NSImage(systemSymbolName: "circle.circle.fill",
                                accessibilityDescription: "Douzi")
            btn.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        } else {
            btn.title = "⦿"
        }
        btn.imageScaling = .scaleProportionallyDown
        btn.imagePosition = .imageOnly

        buildMenu()

        if !isServerListening(port: 5000) {
            startServer()
        }
        updateStatusUI()

        statusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateStatusUI()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
        stopServer()
    }

    // MARK: - 菜单构建

    private func buildMenu() {
        let menu = NSMenu()

        let quickAddItem = NSMenuItem(title: "✨ 快速添加待办", action: #selector(openQuickAdd), keyEquivalent: "n")
        quickAddItem.target = self
        menu.addItem(quickAddItem)

        let openWebItem = NSMenuItem(title: "🌐 打开看板", action: #selector(openWebApp), keyEquivalent: "o")
        openWebItem.target = self
        menu.addItem(openWebItem)

        let organizeItem = NSMenuItem(title: "🧠 一键整理 Inbox", action: #selector(organizeInbox), keyEquivalent: "")
        organizeItem.target = self
        menu.addItem(organizeItem)

        menu.addItem(NSMenuItem.separator())

        let serviceStatusItem = NSMenuItem(title: self.isRunning ? "✅ 服务运行中 (5000)" : "⏹️ 服务已停止", action: nil, keyEquivalent: "")
        serviceStatusItem.isEnabled = false
        serviceStatusItem.tag = 100
        menu.addItem(serviceStatusItem)

        menu.addItem(NSMenuItem.separator())

        let restartItem = NSMenuItem(title: "🔄 重启服务", action: #selector(restartServer), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let stopItem = NSMenuItem(title: "🛑 停止服务", action: #selector(stopServerMenu), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 Douzi", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - 服务管理

    private func startServer() {
        guard !isRunning else { return }

        let fm = FileManager.default
        let nodeBin = findNode()
        let serverScript = projectDir + "/server.mjs"

        guard fm.fileExists(atPath: serverScript) else {
            showAlert(title: "启动失败", message: "找不到 server.mjs，请确保在 Douzi 项目目录下运行。")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: nodeBin)
        task.arguments = [serverScript]
        task.currentDirectoryURL = URL(fileURLWithPath: projectDir)
        task.environment = ProcessInfo.processInfo.environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: nil, attributes: nil)
        }
        guard let fh = FileHandle(forWritingAtPath: logPath) else {
            showAlert(title: "启动失败", message: "无法创建日志文件。")
            return
        }
        fh.seekToEndOfFile()

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            fh.seekToEndOfFile()
            fh.write(data)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            fh.seekToEndOfFile()
            fh.write(data)
        }

        do {
            try task.run()
            serverProcess = task
            isRunning = true
            updateStatusUI()
        } catch {
            showAlert(title: "启动失败", message: "无法启动 Node: \(error.localizedDescription)\n\nnodeBin=\(nodeBin)\nserverScript=\(serverScript)\nprojectDir=\(projectDir)")
        }
    }

    private func stopServer() {
        if let task = serverProcess, task.isRunning {
            task.terminate()
            task.waitUntilExit()
        }
        killProcessOnPort(5000)
        serverProcess = nil
        isRunning = false
        updateStatusUI()
    }

    @objc private func stopServerMenu() {
        stopServer()
    }

    @objc private func restartServer() {
        stopServer()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startServer()
        }
    }

    private func updateStatusUI() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let nowRunning = self.isServerListening(port: 5000)
            self.isRunning = nowRunning
            if let menu = self.statusItem.menu,
               let statusItem = menu.item(withTag: 100) {
                statusItem.title = nowRunning ? "✅ 服务运行中 (5000)" : "⏹️ 服务已停止"
            }
        }
    }

    // MARK: - 功能操作

    @objc private func openQuickAdd() {
        if let w = quickAddWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let swiftUIView = QuickAddView(
            onSubmit: { [weak self] text in
                self?.submitQuickAdd(text: text)
                self?.quickAddWindow?.close()
                self?.quickAddWindow = nil
            },
            onCancel: { [weak self] in
                self?.quickAddWindow?.close()
                self?.quickAddWindow = nil
            }
        )

        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 180)

        let w = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "✨ 快速添加待办"
        w.center()
        w.isReleasedWhenClosed = false
        w.contentView = hostingView

        quickAddWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func submitQuickAdd(text: String) {
        guard !text.isEmpty else { return }

        var req = URLRequest(url: serverURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try? JSONSerialization.data(withJSONObject: ["text": text], options: [])
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { [weak self] _, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    self?.showAlert(title: "添加失败", message: err.localizedDescription)
                    return
                }
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    self?.showAlert(title: "添加失败", message: "服务器返回了错误。")
                    return
                }
                self?.showToast("✅ 已添加到 Inbox")
            }
        }.resume()
    }

    @objc private func openWebApp() {
        if !isRunning {
            startServer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if let url = self?.webURL {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            NSWorkspace.shared.open(webURL)
        }
    }

    @objc private func organizeInbox() {
        let organizeURL = URL(string: "http://127.0.0.1:5000/api/organize")!
        var req = URLRequest(url: organizeURL)
        req.httpMethod = "POST"

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    self?.showAlert(title: "整理失败", message: err.localizedDescription)
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self?.showToast("整理请求已发送 ✅")
                    return
                }
                if let result = json["result"] as? String {
                    self?.showAlert(title: "✨ 整理完成", message: result)
                } else {
                    self?.showToast("整理请求已发送 ✅")
                }
            }
        }.resume()
    }

    @objc private func quitApp() {
        stopServer()
        NSApp.terminate(nil)
    }

    // MARK: - 工具

    private func isServerListening(port: Int) -> Bool {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout.size(ofValue: addr))
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(UInt16(port))
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout.size(ofValue: tv)))

        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                Darwin.connect(fd, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }

    private func killProcessOnPort(_ port: Int) {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "lsof -tiTCP:\(port) | xargs kill -9 2>/dev/null || true".replacingOccurrences(of: "(port)", with: String(port))]
        try? task.run()
        task.waitUntilExit()
    }

    private func which(_ cmd: String) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = [cmd]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func findNode() -> String {
        // 1. Check environment variable set by launcher script (most reliable for GUI apps)
        if let envPath = ProcessInfo.processInfo.environment["DOUZI_NODE_PATH"],
           FileManager.default.fileExists(atPath: envPath) {
            return envPath
        }

        // 2. Try common node locations
        let nodePaths = [
            "/opt/homebrew/bin/node",     // macOS ARM64 Homebrew
            "/usr/local/bin/node",         // macOS Intel Homebrew
            "/opt/local/bin/node",         // macPorts
            "/usr/bin/node",               // system node
        ]
        let fm = FileManager.default
        for path in nodePaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }

        // 3. Fallback to which (works when launched from terminal with proper PATH)
        let found = which("node")
        if let found = found, !found.isEmpty {
            return found
        }

        // 4. Scan nvm versions as last resort
        let nvmBase = NSHomeDirectory() + "/.nvm/versions/node"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: nvmBase) {
            for version in contents.sorted().reversed() {
                let candidate = nvmBase + "/" + version + "/bin/node"
                if fm.fileExists(atPath: candidate) {
                    return candidate
                }
            }
        }
        return "/opt/homebrew/bin/node"
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func showToast(_ message: String) {
        let toast = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toast.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        toast.hasShadow = true
        toast.isOpaque = false
        toast.level = .floating
        toast.collectionBehavior = .canJoinAllSpaces

        let label = NSTextField(labelWithString: message)
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 8, y: 0, width: 184, height: 48)
        label.isBezeled = false
        label.drawsBackground = false
        toast.contentView?.addSubview(label)

        if let screen = NSScreen.main {
            let x = screen.frame.maxX - 220
            let y = screen.frame.maxY - 80
            toast.setFrameOrigin(NSPoint(x: x, y: y))
        }

        toast.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            toast.orderOut(nil)
        }
    }
}
