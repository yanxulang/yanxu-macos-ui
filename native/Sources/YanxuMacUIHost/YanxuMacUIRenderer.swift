import SwiftUI

public typealias YanxuMacUIEventPayload = [String: JSONValue]
public typealias YanxuMacUIEventHandler = (String, YanxuMacUIEventPayload) -> Void

public struct YanxuMacUIRenderer: View {
    @ObservedObject var store: YanxuMacUIApplicationStore
    let windowIndex: Int
    public var onEvent: YanxuMacUIEventHandler

    init(
        store: YanxuMacUIApplicationStore,
        windowIndex: Int,
        onEvent: @escaping YanxuMacUIEventHandler
    ) {
        self.store = store
        self.windowIndex = windowIndex
        self.onEvent = onEvent
    }

    public var body: some View {
        Group {
            if store.application.windows.indices.contains(windowIndex) {
                render(store.application.windows[windowIndex].root)
            } else {
                EmptyView()
            }
        }
        .tint(applicationTint)
    }

    var applicationTint: Color {
        guard let name = store.application.accentColor else { return .accentColor }
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray": return .gray
        case "accentColor": return .accentColor
        default: return name.hasPrefix("#") ? Color(yanxuHex: name) : .accentColor
        }
    }

    func render(_ view: YanxuMacUIView) -> AnyView {
        let rendered = renderControl(view)
            ?? renderLayout(view)
            ?? renderCollection(view)
            ?? renderPresentation(view)
            ?? AnyView(Text("Unsupported view: \(view.kind)").foregroundStyle(.secondary))
        return decorate(rendered, with: view)
    }

    func emit(_ event: String?, source: String, value: JSONValue? = nil) {
        guard let event else { return }
        var payload: YanxuMacUIEventPayload = ["source": .string(source)]
        if let value { payload["value"] = value }
        onEvent(event, payload)
    }

    func emitChange(for view: YanxuMacUIView, value: JSONValue) {
        let event = view.event ?? (view.binding == nil ? nil : "binding.changed")
        guard let event else { return }
        var payload: YanxuMacUIEventPayload = [
            "source": .string(view.stableID),
            "value": value,
            "revision": .number(Double(store.application.revision ?? 0))
        ]
        if let binding = view.binding { payload["binding"] = .string(binding) }
        onEvent(event, payload)
    }
}
