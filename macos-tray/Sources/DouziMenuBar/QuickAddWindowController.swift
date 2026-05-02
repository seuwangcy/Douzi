import Cocoa
import SwiftUI

/// Manages the Quick Add popup window.
final class QuickAddWindowController {

    private var window: NSWindow?
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let swiftUIView = QuickAddView(
            onSubmit: { [weak self] text in
                self?.onSubmit?(text)
                self?.close()
            },
            onCancel: { [weak self] in
                self?.onCancel?()
                self?.close()
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

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}

/// Shared UI alert/toast helpers.
final class UIHelper {

    static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    static func showToast(_ message: String) {
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