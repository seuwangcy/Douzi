import Cocoa

let lockPath = (NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? "/tmp") + "/douzi singleton.lock"

if FileManager.default.fileExists(atPath: lockPath) {
    // 锁存在，先检查端口是否真的有服务在监听
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout.size(ofValue: addr))
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = CFSwapInt16HostToBig(UInt16(5000))
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")

    let fd = socket(AF_INET, SOCK_STREAM, 0)
    let isPortOpen = fd >= 0 && {
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                Darwin.connect(fd, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }() == 0
    if fd >= 0 { close(fd) }

    if isPortOpen {
        // 端口有服务，认为已有实例在运行，发送激活通知
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.douzi.activate"),
            object: nil,
            deliverImmediately: true
        )
        exit(0)
    }
    // 端口无服务，锁文件是残留，直接删除并继续启动
    try? FileManager.default.removeItem(atPath: lockPath)
}

FileManager.default.createFile(atPath: lockPath, contents: nil, attributes: nil)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

try? FileManager.default.removeItem(atPath: lockPath)
