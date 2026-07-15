import AppKit
import SwiftUI

@MainActor
public final class YanxuMacUIAppHost: NSObject, NSApplicationDelegate {
    private var application: YanxuMacUIApplication?
    private var controllers: [NSWindowController] = []
    private var onEvent: YanxuMacUIEventHandler = { _, _ in }

    public func launch(from jsonData: Data, onEvent: @escaping YanxuMacUIEventHandler = { _, _ in }) throws {
        let decoded = try JSONDecoder().decode(YanxuMacUIApplication.self, from: jsonData)
        guard decoded.schema == "dev.yanxu.mac-ui.v1" else {
            throw YanxuMacUIHostError.invalidSchema(decoded.schema)
        }
        guard !decoded.windows.isEmpty else {
            throw YanxuMacUIHostError.noWindows
        }
        self.application = decoded
        self.onEvent = onEvent

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = self
        applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let application else { return }
        for windowDescription in application.windows {
            let root = YanxuMacUIRenderer(view: windowDescription.root, onEvent: onEvent)
            let controller = makeWindowController(for: windowDescription, root: root)
            controllers.append(controller)
            controller.showWindow(nil)
        }
    }

    private func makeWindowController<Root: View>(for description: YanxuMacUIWindow, root: Root) -> NSWindowController {
        let hosting = NSHostingController(rootView: root)
        let size = description.size ?? YanxuMacUISize(width: 900, height: 640)
        let minSize = description.minSize ?? YanxuMacUISize(width: 420, height: 320)
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if description.resizable ?? true {
            style.insert(.resizable)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = description.title
        window.minSize = NSSize(width: minSize.width, height: minSize.height)
        window.center()
        window.contentViewController = hosting
        if let toolbarItems = description.toolbar, !toolbarItems.isEmpty {
            window.toolbar = YanxuMacUIToolbar(items: toolbarItems, onEvent: onEvent)
        }
        return NSWindowController(window: window)
    }
}

public enum YanxuMacUIHostError: Error, CustomStringConvertible {
    case invalidSchema(String)
    case noWindows

    public var description: String {
        switch self {
        case .invalidSchema(let schema): return "Unsupported MacUI schema: \(schema)"
        case .noWindows: return "A macOS application needs at least one window."
        }
    }
}

private final class YanxuMacUIToolbar: NSToolbar, NSToolbarDelegate {
    private let toolbarItems: [YanxuMacUIToolbarItem]
    private let onEvent: YanxuMacUIEventHandler

    init(items: [YanxuMacUIToolbarItem], onEvent: @escaping YanxuMacUIEventHandler) {
        self.toolbarItems = items
        self.onEvent = onEvent
        super.init(identifier: "dev.yanxu.mac-ui.toolbar")
        delegate = self
        displayMode = .iconAndLabel
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarItems.map { NSToolbarItem.Identifier($0.id) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let source = toolbarItems.first(where: { $0.id == itemIdentifier.rawValue }) else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = source.title
        item.paletteLabel = source.title
        item.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: source.title)
        item.target = self
        item.action = #selector(toolbarItemInvoked(_:))
        item.toolTip = source.title
        return item
    }

    @objc private func toolbarItemInvoked(_ sender: NSToolbarItem) {
        guard let source = toolbarItems.first(where: { $0.id == sender.itemIdentifier.rawValue }) else {
            return
        }
        onEvent(source.event, ["source": source.id])
    }
}
