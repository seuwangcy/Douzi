# macOS Menu Bar App (DouziMenuBar)

A native macOS menu bar app that lives in the system tray, providing one-click access to your Douzi GTD board.

## Features

| Menu Item | Shortcut | Action |
|-----------|----------|--------|
| Quick Add Todo | Cmd+N | Opens SwiftUI popup, writes directly to Inbox |
| Open Board | Cmd+O | Auto-starts server if needed, opens localhost:5000 |
| AI Organize Inbox | - | Calls /api/organize, auto-categorizes with Gemini |
| Service Status | - (gray) | Real-time Node.js server status |
| Restart Service | Cmd+R | Kills and restarts node server.mjs |
| Stop Service | - | Terminates Node.js process |
| Quit Douzi | Cmd+Q | Stops service and exits |

## Quick Start

```bash
cd macos-tray
swift build
./.build/debug/DouziMenuBar
```

## Architecture

```
macos-tray/
├── Package.swift                      # SwiftPM config
└── Sources/DouziMenuBar/
    ├── main.swift                     # Entry point: NSApplication + delegate
    ├── AppDelegate.swift              # Core: status bar, menu, server mgmt
    └── QuickAddView.swift             # SwiftUI: quick-add popup
```

| Component | Tech | Notes |
|-----------|------|-------|
| Status bar + menu | AppKit (NSStatusBar, NSMenu) | Native macOS API |
| Quick add popup | SwiftUI via NSHostingView | Modern declarative UI |
| Server management | Foundation (Process, Pipe) | Start/stop/restart node server.mjs |
| Health check | BSD Socket (Darwin.connect) | Lightweight port probe |

## Lessons Learned / Pitfalls

### 1. @main + NSApplicationDelegate launch failure
**Symptom**: Compiles, but nothing happens on run. No icon, no terminal output.
**Cause**: @main annotation incompatible with AppKit runtime init in SwiftPM executables.
**Fix**: Use traditional main.swift entry point:
```swift
import Cocoa
autoreleasepool {
    let app = NSApplication.shared
    app.delegate = AppDelegate()
    app.run()
}
```

### 2. Chinese text "豆" not visible in status bar
**Symptom**: Process runs but no icon in status bar.
**Cause**: variableLength + Chinese characters get compressed to zero width when status bar is crowded.
**Fix**: Use SF Symbols (NSImage(systemSymbolName:)) instead of text or custom drawing.

### 3. Recursive showMenu() crash
**Symptom**: Menu flashes and disappears on first click, then icon vanishes.
**Cause**: Calling statusItem.button?.performClick(nil) inside showMenu(), which triggers itself.
**Fix**: Build menu once at init time; do not dynamically rebuild + self-trigger on click.

### 4. NSStatusBar.system vs systemStatusBar
**Symptom**: Compile error "systemStatusBar renamed to system".
**Fix**: Use NSStatusBar.system.

### 5. StrictConcurrency experimental feature
**Symptom**: Hundreds of Sendable-related compile errors.
**Cause**: .enableExperimentalFeature("StrictConcurrency") in Package.swift incompatible with AppKit+SwiftUI mix.
**Fix**: Remove the feature flag.

### 6. Sandbox cannot compile Swift projects
**Symptom**: swift build fails with sandbox-exec: Operation not permitted.
**Cause**: Swift compiler needs write access to ~/.cache/clang/ and ~/Library/Caches/.
**Fix**: Compile in non-sandboxed local terminal.

## Custom Icon

Current icon uses SF Symbol "circle.circle.fill". To use a custom PNG:
1. Prepare 18x18pt @2x PNG
2. Add to Resources/
3. Replace in AppDelegate.swift:
```swift
btn.image = NSImage(contentsOf: iconUrl)
btn.image?.isTemplate = true
```
