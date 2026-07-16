import AppKit
import SwiftUI

@MainActor
final class YanxuMacUIMenuBarItemController: NSObject {
    let identifier: String
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    var hasStatusButton: Bool { statusItem.button != nil }
    var contentSize: NSSize { popover.contentSize }
    var isPopoverShown: Bool { popover.isShown }

    init(
        description: YanxuMacUIMenuBarItem,
        store: YanxuMacUIApplicationStore,
        onEvent: @escaping YanxuMacUIEventHandler
    ) {
        identifier = description.id
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: YanxuMacUIMenuBarContentView(
                store: store,
                itemID: description.id,
                onEvent: onEvent
            )
        )
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemInvoked(_:))
        }
        update(from: description)
    }

    func update(from description: YanxuMacUIMenuBarItem) {
        popover.contentSize = NSSize(width: description.size.width, height: description.size.height)
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: description.systemName, accessibilityDescription: description.tooltip)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: description.tooltip)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = description.tooltip
        button.setAccessibilityLabel(description.tooltip)
    }

    func invalidate() {
        popover.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(button)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func statusItemInvoked(_ sender: NSStatusBarButton) {
        togglePopover()
    }
}

private struct YanxuMacUIMenuBarContentView: View {
    @ObservedObject var store: YanxuMacUIApplicationStore
    let itemID: String
    let onEvent: YanxuMacUIEventHandler

    var body: some View {
        Group {
            if let item = store.application.menuBarItems?.first(where: { $0.id == itemID }) {
                let renderer = YanxuMacUIRenderer(store: store, windowIndex: 0, onEvent: onEvent)
                renderer.render(item.content)
                    .tint(renderer.applicationTint)
            } else {
                EmptyView()
            }
        }
    }
}
