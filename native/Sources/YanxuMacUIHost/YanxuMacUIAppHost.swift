import AppKit
import SwiftUI

@MainActor
enum YanxuMacUIActiveApplication {
    static weak var host: YanxuMacUIAppHost?
}

@MainActor
public final class YanxuMacUIAppHost: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let terminateApplication: () -> Void
    private let openExternalURL: (URL) -> Bool
    private var store: YanxuMacUIApplicationStore?
    private var controllers: [NSWindowController] = []
    private var controllerIDs: [String] = []
    private var settingsController: NSWindowController?
    private var documentControllers: [String: NSWindowController] = [:]
    private var documentStores: [String: YanxuMacUIApplicationStore] = [:]
    private var documentSceneIDs: [String: String] = [:]
    private var menuBarControllers: [String: YanxuMacUIMenuBarItemController] = [:]
    private var menuTargets: [YanxuMacUIMenuTarget] = []
    private var onEvent: YanxuMacUIEventHandler = { _, _ in }
    private var synchronizingWindows = false
    private var didInstallApplication = false
    private var requestCoordinator: YanxuMacUIRequestCoordinator?
    private var defaultCommandMonitor: Any?
    private var isStopping = false

    public override convenience init() {
        self.init(terminateApplication: { NSApplication.shared.terminate(nil) })
    }

    init(
        terminateApplication: @escaping () -> Void,
        openExternalURL: @escaping (URL) -> Bool = { _ in false }
    ) {
        self.terminateApplication = terminateApplication
        self.openExternalURL = openExternalURL
        super.init()
    }

    public func launch(from jsonData: Data, onEvent: @escaping YanxuMacUIEventHandler = { _, _ in }) throws {
        let decoded = try decodeApplication(jsonData)
        guard YanxuMacUIActiveApplication.host == nil else {
            throw YanxuMacUIHostError.applicationAlreadyRunning
        }

        store = YanxuMacUIApplicationStore(application: decoded)
        self.onEvent = onEvent
        requestCoordinator = YanxuMacUIRequestCoordinator(
            onEvent: onEvent,
            openWindow: { [weak self] in self?.openWindow(identifier: $0) ?? false },
            closeWindow: { [weak self] in self?.closeWindow(identifier: $0) ?? false },
            openSettings: { [weak self] in self?.showSettingsWindow() ?? false },
            openDocument: { [weak self] scene, title, file in
                self?.openDocument(sceneID: scene, title: title, file: file)
            },
            openExternalURL: openExternalURL
        )
        YanxuMacUIActiveApplication.host = self

        let app = NSApplication.shared
        synchronizeActivationPolicy(with: decoded)
        app.delegate = self
        installDefaultCommandMonitor()
        applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        if !isStopping {
            if !decoded.windows.isEmpty { app.activate(ignoringOtherApps: true) }
            app.run()
        }

        YanxuMacUIActiveApplication.host = nil
        app.delegate = nil
        app.mainMenu = nil
        controllers.removeAll()
        controllerIDs.removeAll()
        settingsController = nil
        documentControllers.removeAll()
        documentStores.removeAll()
        documentSceneIDs.removeAll()
        menuBarControllers.values.forEach { $0.invalidate() }
        menuBarControllers.removeAll()
        menuTargets.removeAll()
        store = nil
        requestCoordinator = nil
        if let defaultCommandMonitor {
            NSEvent.removeMonitor(defaultCommandMonitor)
            self.defaultCommandMonitor = nil
        }
        self.onEvent = { _, _ in }
    }

    public func update(from jsonData: Data) throws {
        let decoded = try decodeApplication(jsonData)
        guard let store else { throw YanxuMacUIHostError.noRunningApplication }
        store.update(application: decoded)
        documentStores.values.forEach { $0.updateStructure(application: decoded) }
        synchronizeActivationPolicy(with: decoded)
        synchronizeWindows(with: decoded)
        synchronizeMenuBarItems(with: decoded)
        installMenus(from: decoded)
    }

    public func patch(from jsonData: Data) throws {
        let decoded = try JSONDecoder().decode(YanxuMacUIStatePatch.self, from: jsonData)
        guard decoded.schema == "dev.yanxu.mac-ui.state.v1" else {
            throw YanxuMacUIHostError.invalidSchema(decoded.schema)
        }
        guard decoded.revision >= 0 else { throw YanxuMacUIHostError.invalidRevision }
        guard let store else { throw YanxuMacUIHostError.noRunningApplication }
        let identifiers = decoded.state.map(\.id)
        guard Set(identifiers).count == identifiers.count else {
            throw YanxuMacUIHostError.duplicateIdentifier("state", "patch")
        }
        for state in decoded.state where !state.value.matches(stateType: state.type) {
            throw YanxuMacUIHostError.invalidStateType(state.id, state.type)
        }
        for state in decoded.state where !state.id.isYanxuMacUIIdentifier {
            throw YanxuMacUIHostError.invalidIdentifier("state", state.id)
        }
        let currentTypes = Dictionary(uniqueKeysWithValues: (store.application.state ?? []).map { ($0.id, $0.type) })
        let patchTypes = Dictionary(uniqueKeysWithValues: decoded.state.map { ($0.id, $0.type) })
        guard currentTypes == patchTypes else { throw YanxuMacUIHostError.stateShapeChanged }
        store.patch(decoded)
    }

    public func request(from jsonData: Data) throws {
        let request = try JSONDecoder().decode(YanxuMacUIRequest.self, from: jsonData)
        guard let requestCoordinator else { throw YanxuMacUIHostError.noRunningApplication }
        try requestCoordinator.perform(request)
    }

    func stop() {
        guard !isStopping else { return }
        isStopping = true
        onEvent("application.terminating", [:])
        terminateApplication()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let application = store?.application, !didInstallApplication else { return }
        didInstallApplication = true
        synchronizeWindows(with: application)
        synchronizeMenuBarItems(with: application)
        installMenus(from: application)
        onEvent("application.launched", ["name": .string(application.name)])
    }

    public func windowWillClose(_ notification: Notification) {
        guard !synchronizingWindows else { return }
        guard let window = notification.object as? NSWindow else { return }
        let identifier = window.identifier?.rawValue ?? "settings"
        if documentControllers.removeValue(forKey: identifier) != nil {
            documentStores.removeValue(forKey: identifier)
            documentSceneIDs.removeValue(forKey: identifier)
        }
        onEvent("window.closed", ["window": .string(identifier)])
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        onEvent("window.focused", ["window": .string(window.identifier?.rawValue ?? "settings")])
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        onEvent("application.active", [:])
    }

    public func applicationDidResignActive(_ notification: Notification) {
        onEvent("application.inactive", [:])
    }

    public func applicationWillTerminate(_ notification: Notification) {
        onEvent("application.terminating", [:])
    }

    private func decodeApplication(_ jsonData: Data) throws -> YanxuMacUIApplication {
        let decoded = try JSONDecoder().decode(YanxuMacUIApplication.self, from: jsonData)
        try decoded.validate()
        return decoded
    }

    private func synchronizeWindows(with application: YanxuMacUIApplication) {
        guard let store else { return }
        synchronizingWindows = true
        defer { synchronizingWindows = false }

        let nextIDs = application.windows.enumerated().map { windowIdentifier($0.element, index: $0.offset) }
        for index in controllerIDs.indices.reversed() where !nextIDs.contains(controllerIDs[index]) {
            controllers.remove(at: index).close()
            controllerIDs.remove(at: index)
        }
        for (index, description) in application.windows.enumerated() {
            let identifier = windowIdentifier(description, index: index)
            guard !controllerIDs.contains(identifier) else { continue }
            let root = YanxuMacUIRenderer(store: store, windowID: identifier, onEvent: onEvent)
            let controller = makeWindowController(for: description, root: root)
            controllers.append(controller)
            controllerIDs.append(identifier)
            if description.initiallyVisible ?? true {
                controller.showWindow(nil)
                onEvent("window.opened", ["window": .string(identifier)])
            }
        }
        for (index, description) in application.windows.enumerated() {
            let identifier = windowIdentifier(description, index: index)
            guard let controllerIndex = controllerIDs.firstIndex(of: identifier) else { continue }
            updateWindow(controllers[controllerIndex].window, from: description, identifier: identifier)
        }
    }

    private func synchronizeMenuBarItems(with application: YanxuMacUIApplication) {
        guard let store else { return }
        let descriptions = application.menuBarItems ?? []
        let nextIDs = Set(descriptions.map(\.id))

        let removedIDs = menuBarControllers.keys.filter { !nextIDs.contains($0) }
        for identifier in removedIDs {
            menuBarControllers.removeValue(forKey: identifier)?.invalidate()
        }
        for description in descriptions {
            if let controller = menuBarControllers[description.id] {
                controller.update(from: description)
            } else {
                menuBarControllers[description.id] = YanxuMacUIMenuBarItemController(
                    description: description,
                    store: store,
                    onEvent: onEvent
                )
            }
        }
    }

    private func synchronizeActivationPolicy(with application: YanxuMacUIApplication) {
        let hasApplicationScenes = !application.windows.isEmpty || application.settings != nil || !(application.documents ?? []).isEmpty
        let policy: NSApplication.ActivationPolicy = hasApplicationScenes ? .regular : .accessory
        NSApplication.shared.setActivationPolicy(policy)
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
        window.setContentSize(NSSize(width: size.width, height: size.height))
        updateWindow(window, from: description, identifier: description.id ?? "window")
        return NSWindowController(window: window)
    }

    private func updateWindow(_ window: NSWindow?, from description: YanxuMacUIWindow, identifier: String) {
        guard let window else { return }
        let minSize = description.minSize ?? YanxuMacUISize(width: 420, height: 320)
        window.title = description.title
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        if let restorationID = description.restorationID ?? description.id {
            window.setFrameAutosaveName(restorationID)
        }
        window.minSize = NSSize(width: minSize.width, height: minSize.height)
        if description.resizable ?? true {
            window.styleMask.insert(.resizable)
        } else {
            window.styleMask.remove(.resizable)
        }
        if let toolbarItems = description.toolbar, !toolbarItems.isEmpty, let store {
            window.toolbar = YanxuMacUIToolbar(items: toolbarItems, store: store, onEvent: onEvent)
        } else {
            window.toolbar = nil
        }
    }

    private func windowIdentifier(_ description: YanxuMacUIWindow, index: Int) -> String {
        description.id ?? "window-\(index)"
    }

    private func openWindow(identifier: String) -> Bool {
        guard let index = controllerIDs.firstIndex(of: identifier) else { return false }
        controllers[index].showWindow(nil)
        controllers[index].window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        onEvent("window.opened", ["window": .string(identifier)])
        return true
    }

    private func closeWindow(identifier: String) -> Bool {
        if let index = controllerIDs.firstIndex(of: identifier) {
            controllers[index].close()
            return true
        }
        if let controller = documentControllers.removeValue(forKey: identifier) {
            documentStores.removeValue(forKey: identifier)
            controller.close()
            return true
        }
        return false
    }

    private func showSettingsWindow() -> Bool {
        guard let store, store.application.settings != nil else { return false }
        if settingsController == nil {
            let root = YanxuMacUISettingsContentView(store: store, onEvent: onEvent)
            let size = store.application.settingsSize ?? YanxuMacUISize(width: 620, height: 480)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.identifier = NSUserInterfaceItemIdentifier("settings")
            window.delegate = self
            window.center()
            window.contentViewController = NSHostingController(rootView: root)
            window.setContentSize(NSSize(width: size.width, height: size.height))
            settingsController = NSWindowController(window: window)
        }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        onEvent("settings.opened", [:])
        return true
    }

    private func installMenus(from application: YanxuMacUIApplication) {
        let mainMenu = NSMenu(title: application.name)
        menuTargets.removeAll()
        let applicationItem = NSMenuItem(title: application.name, action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: application.name)
        if application.settings != nil {
            let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
            settingsItem.target = self
            applicationMenu.addItem(settingsItem)
            applicationMenu.addItem(.separator())
        }
        let quitItem = NSMenuItem(title: "Quit \(application.name)", action: #selector(quitFromMenu(_:)), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        var systemFileMenu: NSMenu?
        if let document = application.documents?.first {
            let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            let fileMenu = NSMenu(title: "File")
            let newItem = NSMenuItem(title: "New", action: #selector(newDocumentFromMenu(_:)), keyEquivalent: "n")
            newItem.target = self
            newItem.representedObject = document.id
            fileMenu.addItem(newItem)
            let openItem = NSMenuItem(title: "Open...", action: #selector(openDocumentFromMenu(_:)), keyEquivalent: "o")
            openItem.target = self
            openItem.representedObject = document.id
            fileMenu.addItem(openItem)
            let saveItem = NSMenuItem(title: "Save", action: #selector(saveDocumentFromMenu(_:)), keyEquivalent: "s")
            saveItem.target = self
            fileMenu.addItem(saveItem)
            fileItem.submenu = fileMenu
            mainMenu.addItem(fileItem)
            systemFileMenu = fileMenu
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        let menus = (application.menus ?? []).sorted {
            menuPlacementRank($0.placement) < menuPlacementRank($1.placement)
        }
        for menuDescription in menus {
            let reusesSystemFileMenu = menuDescription.placement == "file" && systemFileMenu != nil
            let rootItem = NSMenuItem(title: menuDescription.title, action: nil, keyEquivalent: "")
            let submenu = reusesSystemFileMenu ? systemFileMenu! : NSMenu(title: menuDescription.title)
            if reusesSystemFileMenu, !submenu.items.isEmpty { submenu.addItem(.separator()) }
            for command in menuDescription.items ?? [] {
                let target = YanxuMacUIMenuTarget(command: command, store: store, onEvent: onEvent)
                menuTargets.append(target)
                let item = NSMenuItem(
                    title: command.title,
                    action: #selector(YanxuMacUIMenuTarget.invoke(_:)),
                    keyEquivalent: command.shortcut?.key ?? ""
                )
                item.target = target
                if let stateBinding = command.stateBinding {
                    item.state = store?.value(for: stateBinding).boolValue == true ? .on : .off
                }
                if let modifiers = command.shortcut?.modifiers {
                    item.keyEquivalentModifierMask = modifierFlags(modifiers)
                }
                submenu.addItem(item)
            }
            if !reusesSystemFileMenu {
                rootItem.submenu = submenu
                mainMenu.addItem(rootItem)
            }
        }
        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        _ = showSettingsWindow()
    }

    @objc private func quitFromMenu(_ sender: Any?) {
        stop()
    }

    @objc private func newDocumentFromMenu(_ sender: NSMenuItem) {
        guard let sceneID = sender.representedObject as? String else { return }
        _ = openDocument(sceneID: sceneID, title: nil, file: nil)
    }

    @objc private func openDocumentFromMenu(_ sender: NSMenuItem) {
        guard let sceneID = sender.representedObject as? String else { return }
        guard let scene = store?.application.documents?.first(where: { $0.id == sceneID }) else { return }
        let request = YanxuMacUIRequest(
            id: "system-open-\(UUID().uuidString.lowercased())",
            type: "document.open",
            sceneID: sceneID,
            allowedTypes: scene.contentTypes
        )
        try? requestCoordinator?.perform(request)
    }

    @objc private func saveDocumentFromMenu(_ sender: NSMenuItem) {
        guard let documentID = NSApplication.shared.keyWindow?.identifier?.rawValue,
              let documentStore = documentStores[documentID],
              let sceneID = documentSceneIDs[documentID],
              let scene = store?.application.documents?.first(where: { $0.id == sceneID }) else { return }
        let content = scene.contentBinding.map {
            documentStore.value(for: $0, fallback: .string("")).stringValue
        } ?? ""
        let request = YanxuMacUIRequest(
            id: "system-save-\(UUID().uuidString.lowercased())",
            type: "document.save",
            windowID: documentID,
            sceneID: sceneID,
            allowedTypes: scene.contentTypes,
            suggestedName: NSApplication.shared.keyWindow?.title ?? scene.defaultFilename,
            content: content
        )
        try? requestCoordinator?.perform(request)
    }

    private func openDocument(sceneID: String, title: String?, file: [String: JSONValue]?) -> String? {
        guard let store,
              let scene = store.application.documents?.first(where: { $0.id == sceneID }) else { return nil }
        let identifier = "document-\(UUID().uuidString.lowercased())"
        let documentStore = YanxuMacUIApplicationStore(application: store.application)
        if let binding = scene.contentBinding, let content = file?["content"] {
            documentStore.setValue(content, forBinding: binding)
        }
        if let binding = scene.pathBinding, let path = file?["path"] {
            documentStore.setValue(path, forBinding: binding)
        }
        let content = YanxuMacUIDocumentContentView(
            store: documentStore,
            sceneID: sceneID,
            documentID: identifier,
            onEvent: onEvent
        )
        let size = scene.size ?? YanxuMacUISize(width: 900, height: 640)
        let minSize = scene.minSize ?? YanxuMacUISize(width: 420, height: 320)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title ?? scene.defaultFilename ?? scene.title
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.minSize = NSSize(width: minSize.width, height: minSize.height)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(NSSize(width: size.width, height: size.height))
        window.cascadeTopLeft(from: NSPoint(x: 80, y: 760))
        let controller = NSWindowController(window: window)
        documentControllers[identifier] = controller
        documentStores[identifier] = documentStore
        documentSceneIDs[identifier] = sceneID
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        onEvent("document.window.opened", [
            "document": .string(identifier),
            "scene": .string(sceneID)
        ])
        return identifier
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

    private func menuPlacementRank(_ placement: String?) -> Int {
        switch placement {
        case "file": return 10
        case "edit": return 20
        case "view": return 30
        case "window": return 40
        case "help": return 50
        default: return 35
        }
    }

    private func installDefaultCommandMonitor() {
        defaultCommandMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.keyCode == 36,
                  let identifier = NSApplication.shared.keyWindow?.identifier?.rawValue,
                  let description = self.store?.application.windows.enumerated().first(where: {
                      ($0.element.id ?? "window-\($0.offset)") == identifier
                  })?.element,
                  let command = description.defaultCommand else { return event }
            self.onEvent(command, ["source": .string(identifier), "context": .string("default")])
            return nil
        }
    }
}

private struct YanxuMacUISettingsContentView: View {
    @ObservedObject var store: YanxuMacUIApplicationStore
    let onEvent: YanxuMacUIEventHandler

    var body: some View {
        Group {
            if let settings = store.application.settings {
                let renderer = YanxuMacUIRenderer(store: store, windowIndex: 0, onEvent: onEvent)
                renderer.render(settings).tint(renderer.applicationTint)
            } else {
                EmptyView()
            }
        }
    }
}

private struct YanxuMacUIDocumentContentView: View {
    @ObservedObject var store: YanxuMacUIApplicationStore
    let sceneID: String
    let documentID: String
    let onEvent: YanxuMacUIEventHandler

    var body: some View {
        Group {
            if let scene = store.application.documents?.first(where: { $0.id == sceneID }) {
                let renderer = YanxuMacUIRenderer(store: store, windowIndex: 0) { name, payload in
                    var scopedPayload = payload
                    scopedPayload["document"] = .string(documentID)
                    scopedPayload["scene"] = .string(sceneID)
                    onEvent(name, scopedPayload)
                }
                renderer.render(scene.root)
                    .tint(renderer.applicationTint)
            } else {
                EmptyView()
            }
        }
    }
}

public enum YanxuMacUIHostError: Error, CustomStringConvertible {
    case invalidSchema(String)
    case noPresentationAnchor
    case noRunningApplication
    case applicationAlreadyRunning
    case duplicateIdentifier(String, String)
    case invalidStateType(String, String)
    case boundViewNeedsIdentifier(String)
    case unknownBinding(String)
    case bindingTypeMismatch(String, String, String)
    case stateShapeChanged
    case invalidRevision
    case invalidIdentifier(String, String)
    case unsupportedBindingType(String, String)
    case invalidControlConfiguration(String)
    case invalidMenuBarItem(String)
    case invalidDocumentScene(String)
    case commandBindingTypeMismatch(String)
    case focusBindingTypeMismatch(String)
    case unsupportedRequest(String)
    case fileTooLarge
    case invalidFileContent
    case documentBindingTypeMismatch(String)

    public var description: String {
        switch self {
        case .invalidSchema(let schema): return "Unsupported MacUI schema: \(schema)"
        case .noPresentationAnchor: return "A macOS application needs at least one window or menu bar item."
        case .noRunningApplication: return "No macOS UI application is running."
        case .applicationAlreadyRunning: return "A macOS UI application is already running."
        case .duplicateIdentifier(let kind, let id): return "Duplicate \(kind) identifier: \(id)"
        case .invalidStateType(let id, let type): return "State \(id) has a value incompatible with type \(type)."
        case .boundViewNeedsIdentifier(let kind): return "Bound \(kind) views need an explicit stable identifier."
        case .unknownBinding(let id): return "View references unknown state binding: \(id)"
        case .bindingTypeMismatch(let id, let actual, let expected):
            return "Binding \(id) has type \(actual), expected \(expected)."
        case .stateShapeChanged: return "State patches cannot add, remove, or retype application state."
        case .invalidRevision: return "Schema v2 requires a non-negative revision."
        case .invalidIdentifier(let kind, let id): return "Invalid \(kind) identifier: \(id)"
        case .unsupportedBindingType(let kind, let type): return "\(kind) does not support \(type) bindings."
        case .invalidControlConfiguration(let kind): return "\(kind) requires minimum < maximum and step > 0."
        case .invalidMenuBarItem(let id): return "Menu bar item \(id) has an invalid icon, tooltip, or popover size."
        case .invalidDocumentScene(let id): return "Document scene \(id) needs at least one content type."
        case .commandBindingTypeMismatch(let id): return "Command state binding \(id) must reference boolean state."
        case .focusBindingTypeMismatch(let id): return "Focus binding \(id) must reference string state."
        case .unsupportedRequest(let type): return "Unsupported application request: \(type)"
        case .fileTooLarge: return "File requests are limited to 16 MiB per file."
        case .invalidFileContent: return "The request contains invalid encoded file content."
        case .documentBindingTypeMismatch(let id): return "Document binding \(id) must reference string state."
        }
    }
}

private final class YanxuMacUIToolbar: NSToolbar, NSToolbarDelegate, NSToolbarItemValidation {
    private let toolbarItems: [YanxuMacUIToolbarItem]
    private weak var store: YanxuMacUIApplicationStore?
    private let onEvent: YanxuMacUIEventHandler

    init(items: [YanxuMacUIToolbarItem], store: YanxuMacUIApplicationStore, onEvent: @escaping YanxuMacUIEventHandler) {
        toolbarItems = items
        self.store = store
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
        item.image = NSImage(systemSymbolName: source.systemName ?? "circle", accessibilityDescription: source.title)
        item.target = self
        item.action = #selector(toolbarItemInvoked(_:))
        item.toolTip = source.title
        item.isNavigational = source.placement == "navigation"
        item.visibilityPriority = source.placement == "primary" ? .high : .standard
        return item
    }

    @objc private func toolbarItemInvoked(_ sender: NSToolbarItem) {
        guard let source = toolbarItems.first(where: { $0.id == sender.itemIdentifier.rawValue }) else { return }
        onEvent(source.event, ["source": .string(source.id)])
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard let source = toolbarItems.first(where: { $0.id == item.itemIdentifier.rawValue }),
              let binding = source.enabledBinding else { return true }
        return store?.value(for: binding, fallback: .bool(false)).boolValue == true
    }
}

private final class YanxuMacUIMenuTarget: NSObject, NSMenuItemValidation {
    private let command: YanxuMacUICommand
    private weak var store: YanxuMacUIApplicationStore?
    private let onEvent: YanxuMacUIEventHandler

    init(command: YanxuMacUICommand, store: YanxuMacUIApplicationStore?, onEvent: @escaping YanxuMacUIEventHandler) {
        self.command = command
        self.store = store
        self.onEvent = onEvent
    }

    @objc func invoke(_ sender: NSMenuItem) {
        var payload: YanxuMacUIEventPayload = [
            "source": .string(command.id ?? sender.title),
            "role": .string(command.role ?? "normal")
        ]
        if let binding = command.stateBinding {
            let next = !(store?.value(for: binding, fallback: .bool(false)).boolValue ?? false)
            store?.setValue(.bool(next), forBinding: binding)
            payload["binding"] = .string(binding)
            payload["value"] = .bool(next)
            payload["revision"] = .number(Double(store?.application.revision ?? 0))
        }
        onEvent(command.event, payload)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let binding = command.stateBinding {
            menuItem.state = store?.value(for: binding, fallback: .bool(false)).boolValue == true ? .on : .off
        }
        guard let binding = command.enabledBinding else { return true }
        return store?.value(for: binding, fallback: .bool(false)).boolValue == true
    }
}
