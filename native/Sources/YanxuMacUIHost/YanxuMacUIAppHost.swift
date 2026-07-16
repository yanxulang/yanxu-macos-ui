import AppKit
import SwiftUI

@MainActor
enum YanxuMacUIActiveApplication {
    static weak var host: YanxuMacUIAppHost?
}

@MainActor
public final class YanxuMacUIAppHost: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: YanxuMacUIApplicationStore?
    private var controllers: [NSWindowController] = []
    private var menuTargets: [YanxuMacUIMenuTarget] = []
    private var onEvent: YanxuMacUIEventHandler = { _, _ in }
    private var synchronizingWindows = false

    public func launch(from jsonData: Data, onEvent: @escaping YanxuMacUIEventHandler = { _, _ in }) throws {
        let decoded = try decodeApplication(jsonData)
        guard YanxuMacUIActiveApplication.host == nil else {
            throw YanxuMacUIHostError.applicationAlreadyRunning
        }

        store = YanxuMacUIApplicationStore(application: decoded)
        self.onEvent = onEvent
        YanxuMacUIActiveApplication.host = self

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = self
        applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        app.activate(ignoringOtherApps: true)
        app.run()

        YanxuMacUIActiveApplication.host = nil
        app.delegate = nil
        app.mainMenu = nil
        controllers.removeAll()
        menuTargets.removeAll()
        store = nil
    }

    public func update(from jsonData: Data) throws {
        let decoded = try decodeApplication(jsonData)
        guard let store else { throw YanxuMacUIHostError.noRunningApplication }
        store.update(application: decoded)
        synchronizeWindows(with: decoded)
        installMenus(from: decoded)
    }

    func stop() {
        NSApplication.shared.stop(nil)
        wakeApplicationRunLoop()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let application = store?.application, controllers.isEmpty else { return }
        synchronizeWindows(with: application)
        installMenus(from: application)
    }

    public func windowWillClose(_ notification: Notification) {
        guard !synchronizingWindows else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.controllers.allSatisfy({ $0.window?.isVisible != true }) else { return }
            self.stop()
        }
    }

    private func decodeApplication(_ jsonData: Data) throws -> YanxuMacUIApplication {
        let decoded = try JSONDecoder().decode(YanxuMacUIApplication.self, from: jsonData)
        guard decoded.schema == "dev.yanxu.mac-ui.v1" else {
            throw YanxuMacUIHostError.invalidSchema(decoded.schema)
        }
        guard !decoded.windows.isEmpty else {
            throw YanxuMacUIHostError.noWindows
        }
        return decoded
    }

    private func synchronizeWindows(with application: YanxuMacUIApplication) {
        guard let store else { return }
        synchronizingWindows = true
        defer { synchronizingWindows = false }

        while controllers.count < application.windows.count {
            let index = controllers.count
            let description = application.windows[index]
            let root = YanxuMacUIRenderer(store: store, windowIndex: index, onEvent: onEvent)
            let controller = makeWindowController(for: description, root: root)
            controllers.append(controller)
            controller.showWindow(nil)
        }
        while controllers.count > application.windows.count {
            controllers.removeLast().close()
        }
        for (index, description) in application.windows.enumerated() {
            updateWindow(controllers[index].window, from: description)
        }
    }

    private func makeWindowController<Root: View>(for description: YanxuMacUIWindow, root: Root) -> NSWindowController {
        let hosting = NSHostingController(rootView: root)
        let size = description.size ?? YanxuMacUISize(width: 900, height: 640)
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if description.resizable ?? true { style.insert(.resizable) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.center()
        window.contentViewController = hosting
        updateWindow(window, from: description)
        return NSWindowController(window: window)
    }

    private func updateWindow(_ window: NSWindow?, from description: YanxuMacUIWindow) {
        guard let window else { return }
        let minSize = description.minSize ?? YanxuMacUISize(width: 420, height: 320)
        window.title = description.title
        window.minSize = NSSize(width: minSize.width, height: minSize.height)
        if description.resizable ?? true {
            window.styleMask.insert(.resizable)
        } else {
            window.styleMask.remove(.resizable)
        }
        if let toolbarItems = description.toolbar, !toolbarItems.isEmpty {
            window.toolbar = YanxuMacUIToolbar(items: toolbarItems, onEvent: onEvent)
        } else {
            window.toolbar = nil
        }
    }

    private func installMenus(from application: YanxuMacUIApplication) {
        let mainMenu = NSMenu(title: application.name)
        menuTargets.removeAll()
        for menuDescription in application.menus ?? [] {
            let rootItem = NSMenuItem(title: menuDescription.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: menuDescription.title)
            for command in menuDescription.items ?? [] {
                let target = YanxuMacUIMenuTarget(event: command.event, onEvent: onEvent)
                menuTargets.append(target)
                let item = NSMenuItem(
                    title: command.title,
                    action: #selector(YanxuMacUIMenuTarget.invoke(_:)),
                    keyEquivalent: command.shortcut?.key ?? ""
                )
                item.target = target
                if let modifiers = command.shortcut?.modifiers {
                    item.keyEquivalentModifierMask = modifierFlags(modifiers)
                }
                submenu.addItem(item)
            }
            rootItem.submenu = submenu
            mainMenu.addItem(rootItem)
        }
        NSApplication.shared.mainMenu = mainMenu
    }

    private func modifierFlags(_ names: [String]) -> NSEvent.ModifierFlags {
        names.reduce(into: []) { flags, name in
            switch name {
            case "command": flags.insert(.command)
            case "option": flags.insert(.option)
            case "control": flags.insert(.control)
            case "shift": flags.insert(.shift)
            default: break
            }
        }
    }

    private func wakeApplicationRunLoop() {
        guard let event = NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        ) else { return }
        NSApplication.shared.postEvent(event, atStart: false)
    }
}

public enum YanxuMacUIHostError: Error, CustomStringConvertible {
    case invalidSchema(String)
    case noWindows
    case noRunningApplication
    case applicationAlreadyRunning

    public var description: String {
        switch self {
        case .invalidSchema(let schema): return "Unsupported MacUI schema: \(schema)"
        case .noWindows: return "A macOS application needs at least one window."
        case .noRunningApplication: return "No macOS UI application is running."
        case .applicationAlreadyRunning: return "A macOS UI application is already running."
        }
    }
}

private final class YanxuMacUIToolbar: NSToolbar, NSToolbarDelegate {
    private let toolbarItems: [YanxuMacUIToolbarItem]
    private let onEvent: YanxuMacUIEventHandler

    init(items: [YanxuMacUIToolbarItem], onEvent: @escaping YanxuMacUIEventHandler) {
        toolbarItems = items
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

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let source = toolbarItems.first(where: { $0.id == itemIdentifier.rawValue }) else { return nil }
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
        guard let source = toolbarItems.first(where: { $0.id == sender.itemIdentifier.rawValue }) else { return }
        onEvent(source.event, ["source": .string(source.id)])
    }
}

private final class YanxuMacUIMenuTarget: NSObject {
    private let event: String
    private let onEvent: YanxuMacUIEventHandler

    init(event: String, onEvent: @escaping YanxuMacUIEventHandler) {
        self.event = event
        self.onEvent = onEvent
    }

    @objc func invoke(_ sender: NSMenuItem) {
        onEvent(event, ["source": .string(sender.title)])
    }
}
