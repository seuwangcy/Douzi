import Foundation

/// Manages the Node.js server lifecycle.
final class ServerManager {

    static let shared = ServerManager()

    private var serverProcess: Process?
    private var isRunning = false
    private let port: Int

    let logPath: String
    let serverURL = URL(string: "http://127.0.0.1:5000/api/quick-add")!
    let webURL = URL(string: "http://127.0.0.1:5000")!

    var onStatusChanged: ((Bool) -> Void)?

    private init() {
        let projectDir = ServerManager.deriveProjectDir()
        self.logPath = projectDir + "/.douzi-server.log"
        self.port = 5000
    }

    var running: Bool { isRunning }

    func start() {
        guard !isRunning else { return }

        let fm = FileManager.default
        let nodeBin = findNode()
        let projectDir = ServerManager.deriveProjectDir()
        let serverScript = projectDir + "/server.mjs"

        guard fm.fileExists(atPath: serverScript) else {
            NotificationCenter.default.post(name: .serverError, object: "找不到 server.mjs")
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
            NotificationCenter.default.post(name: .serverError, object: "无法创建日志文件")
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
            onStatusChanged?(true)
        } catch {
            NotificationCenter.default.post(
                name: .serverError,
                object: "无法启动 Node: \(error.localizedDescription)\n\nnodeBin=\(nodeBin)"
            )
        }
    }

    func stop() {
        if let task = serverProcess, task.isRunning {
            task.terminate()
            task.waitUntilExit()
        }
        killProcessOnPort(port)
        serverProcess = nil
        isRunning = false
        onStatusChanged?(false)
    }

    func restart() {
        stop()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
        }
    }

    func checkStatus() -> Bool {
        let wasRunning = isRunning
        isRunning = isServerListening(port: port)
        if wasRunning != isRunning {
            onStatusChanged?(isRunning)
        }
        return isRunning
    }

    func submitQuickAdd(text: String, completion: @escaping (Error?) -> Void) {
        var req = URLRequest(url: serverURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try? JSONSerialization.data(withJSONObject: ["text": text], options: [])
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { _, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(err)
                    return
                }
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    completion(NSError(domain: "Server", code: -1, userInfo: [NSLocalizedDescriptionKey: "服务器返回错误"]))
                    return
                }
                completion(nil)
            }
        }.resume()
    }

    func organizeInbox(completion: @escaping (String?) -> Void) {
        let organizeURL = URL(string: "http://127.0.0.1:5000/api/organize")!
        var req = URLRequest(url: organizeURL)
        req.httpMethod = "POST"

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if err != nil {
                    completion(nil)
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = json["result"] as? String else {
                    completion(nil)
                    return
                }
                completion(result)
            }
        }.resume()
    }

    // MARK: - Private

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
        task.arguments = ["-c", "lsof -tiTCP:\(port) | xargs kill -9 2>/dev/null || true"]
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
        if let envPath = ProcessInfo.processInfo.environment["DOUZI_NODE_PATH"],
           FileManager.default.fileExists(atPath: envPath) {
            return envPath
        }

        let nodePaths = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/opt/local/bin/node",
            "/usr/bin/node",
        ]
        let fm = FileManager.default
        for path in nodePaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }

        let found = which("node")
        if let found = found, !found.isEmpty {
            return found
        }

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

    static func deriveProjectDir() -> String {
        let fm = FileManager.default
        let execPath = Bundle.main.executablePath ?? ""
        let execURL = URL(fileURLWithPath: execPath)
        let execDir = execURL.deletingLastPathComponent().path

        var projectDirCandidate: String

        if execDir.hasSuffix("/Contents/MacOS") {
            let homeDir = NSHomeDirectory()
            projectDirCandidate = homeDir + "/.douzi"
        } else {
            let macosTrayDir = (execDir as NSString).deletingLastPathComponent
            let buildDir = (macosTrayDir as NSString).deletingLastPathComponent
            let parentDir = (buildDir as NSString).deletingLastPathComponent

            if fm.fileExists(atPath: parentDir + "/server.mjs") {
                projectDirCandidate = parentDir
            } else {
                let step1 = (execDir as NSString).deletingLastPathComponent
                let step2 = (step1 as NSString).deletingLastPathComponent
                let step3 = (step2 as NSString).deletingLastPathComponent
                let step4 = (step3 as NSString).deletingLastPathComponent
                projectDirCandidate = step4
            }
        }

        if fm.fileExists(atPath: projectDirCandidate + "/server.mjs") {
            return projectDirCandidate
        } else {
            return fm.currentDirectoryPath
        }
    }
}

extension Notification.Name {
    static let serverError = Notification.Name("com.douzi.serverError")
    static let serverStatusChanged = Notification.Name("com.douzi.serverStatusChanged")
}