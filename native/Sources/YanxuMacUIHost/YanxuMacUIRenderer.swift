import AppKit
import SwiftUI

public typealias YanxuMacUIEventPayload = [String: JSONValue]
public typealias YanxuMacUIEventHandler = (String, YanxuMacUIEventPayload) -> Void

final class YanxuMacUIApplicationStore: ObservableObject {
    @Published private(set) var application: YanxuMacUIApplication
    private var controlValues: [String: JSONValue] = [:]
    private var modelControlValues: [String: JSONValue] = [:]

    init(application: YanxuMacUIApplication) {
        self.application = application
        modelControlValues = collectControlValues(from: application)
        controlValues = modelControlValues
    }

    func update(application: YanxuMacUIApplication) {
        let nextModelValues = collectControlValues(from: application)
        var nextControlValues: [String: JSONValue] = [:]
        for (identifier, modelValue) in nextModelValues {
            if modelControlValues[identifier] == modelValue, let localValue = controlValues[identifier] {
                nextControlValues[identifier] = localValue
            } else {
                nextControlValues[identifier] = modelValue
            }
        }
        modelControlValues = nextModelValues
        controlValues = nextControlValues
        self.application = application
    }

    func value(for view: YanxuMacUIView, fallback: JSONValue) -> JSONValue {
        controlValues[view.stableID] ?? view.value ?? fallback
    }

    func setValue(_ value: JSONValue, for view: YanxuMacUIView) {
        objectWillChange.send()
        controlValues[view.stableID] = value
    }

    private func collectControlValues(from application: YanxuMacUIApplication) -> [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        for window in application.windows {
            collectControlValues(from: window.root, into: &values)
        }
        return values
    }

    private func collectControlValues(from view: YanxuMacUIView, into values: inout [String: JSONValue]) {
        switch view.kind {
        case "TextField", "TextEditor":
            values[view.stableID] = view.value ?? .string("")
        case "SecureField":
            values[view.stableID] = .string("")
        case "Toggle":
            values[view.stableID] = view.value ?? .bool(false)
        default:
            break
        }
        for child in view.children ?? [] {
            collectControlValues(from: child, into: &values)
        }
    }
}

public struct YanxuMacUIRenderer: View {
    @ObservedObject private var store: YanxuMacUIApplicationStore
    private let windowIndex: Int
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
    }

    private func render(_ view: YanxuMacUIView) -> AnyView {
        let rendered: AnyView
        switch view.kind {
        case "Text":
            rendered = AnyView(Text(view.text ?? ""))
        case "Button":
            rendered = AnyView(Button(view.title ?? "Button") {
                emit(view.event, source: view.stableID)
            })
        case "TextField":
            rendered = AnyView(TextField(view.placeholder ?? "", text: textBinding(for: view))
                .textFieldStyle(.roundedBorder))
        case "SecureField":
            rendered = AnyView(SecureField(view.placeholder ?? "", text: textBinding(for: view))
                .textFieldStyle(.roundedBorder))
        case "TextEditor":
            rendered = AnyView(TextEditor(text: textBinding(for: view))
                .font(.body)
                .frame(minHeight: 120))
        case "Toggle":
            rendered = AnyView(Toggle(view.title ?? "", isOn: boolBinding(for: view)))
        case "Image":
            rendered = AnyView(Image(systemName: view.systemName ?? "app")
                .imageScale(.large))
        case "Spacer":
            rendered = AnyView(Spacer(minLength: view.size.map { CGFloat($0) }))
        case "HStack":
            rendered = AnyView(HStack(spacing: spacing(for: view)) {
                ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in
                    render(child)
                }
            })
        case "VStack":
            rendered = AnyView(VStack(alignment: .leading, spacing: spacing(for: view)) {
                ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in
                    render(child)
                }
            })
        case "ScrollView":
            rendered = AnyView(ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in
                        render(child)
                    }
                }
            })
        case "GroupBox":
            rendered = AnyView(GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in
                        render(child)
                    }
                }
            })
        case "Form":
            rendered = AnyView(Form {
                ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in
                    render(child)
                }
            })
        case "NavigationSplitView":
            let children = view.children ?? []
            rendered = AnyView(NavigationSplitView {
                if children.indices.contains(0) { render(children[0]) }
            } content: {
                if children.indices.contains(1) { render(children[1]) }
            } detail: {
                if children.indices.contains(2) { render(children[2]) }
            })
        case "Divider":
            rendered = AnyView(Divider())
        case "ProgressView":
            rendered = AnyView(ProgressView(value: view.valueNumber))
        case "TabView":
            rendered = AnyView(TabView {
                ForEach(Array((view.items ?? []).enumerated()), id: \.offset) { index, item in
                    Text(item.stringValue)
                        .tabItem { Text("Tab \(index + 1)") }
                }
            })
        case "List":
            rendered = AnyView(List(Array((view.items ?? []).enumerated()), id: \.offset) { _, item in
                Text(item.stringValue)
            })
        default:
            rendered = AnyView(Text("Unsupported view: \(view.kind)")
                .foregroundStyle(.secondary))
        }
        return decorate(rendered, with: view)
    }

    private func textBinding(for view: YanxuMacUIView) -> Binding<String> {
        Binding(
            get: { store.value(for: view, fallback: .string("")).stringValue },
            set: { value in
                store.setValue(.string(value), for: view)
                emit(view.event, source: view.stableID, value: .string(value))
            }
        )
    }

    private func boolBinding(for view: YanxuMacUIView) -> Binding<Bool> {
        Binding(
            get: { store.value(for: view, fallback: .bool(false)).boolValue },
            set: { value in
                store.setValue(.bool(value), for: view)
                emit(view.event, source: view.stableID, value: .bool(value))
            }
        )
    }

    private func emit(_ event: String?, source: String, value: JSONValue? = nil) {
        guard let event else { return }
        var payload: YanxuMacUIEventPayload = ["source": .string(source)]
        if let value { payload["value"] = value }
        onEvent(event, payload)
    }

    private func decorate(_ content: AnyView, with view: YanxuMacUIView) -> AnyView {
        var result = AnyView(content
            .disabled(view.disabled ?? false)
            .modifier(YanxuMacUIStyleModifier(style: view.style)))
        if let help = view.help {
            result = AnyView(result.help(help))
        }
        if let label = view.accessibilityLabel {
            result = AnyView(result.accessibilityLabel(label))
        }
        return result
    }

    private func spacing(for view: YanxuMacUIView) -> Double {
        if case .number(let value) = view.style?["spacing"] {
            return value
        }
        return 8
    }
}

private extension YanxuMacUIView {
    var valueNumber: Double {
        if case .number(let value) = value { return value }
        return 0
    }
}

private struct YanxuMacUIStyleModifier: ViewModifier {
    var style: [String: JSONValue]?

    func body(content: Content) -> some View {
        var result = AnyView(content)
        if case .number(let padding) = style?["padding"] {
            result = AnyView(result.padding(padding))
        }
        if case .string(let weight) = style?["weight"], weight == "semibold" {
            result = AnyView(result.fontWeight(.semibold))
        }
        if case .string(let font) = style?["font"] {
            result = AnyView(result.font(fontValue(font)))
        }
        return result
    }

    private func fontValue(_ name: String) -> Font {
        switch name {
        case "largeTitle": return .largeTitle
        case "title": return .title
        case "title2": return .title2
        case "headline": return .headline
        case "caption": return .caption
        default: return .body
        }
    }
}
