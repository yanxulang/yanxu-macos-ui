import AppKit
import SwiftUI

public typealias YanxuMacUIEventHandler = (String, [String: String]) -> Void

public struct YanxuMacUIRenderer: View {
    public var view: YanxuMacUIView
    public var onEvent: YanxuMacUIEventHandler

    public init(view: YanxuMacUIView, onEvent: @escaping YanxuMacUIEventHandler) {
        self.view = view
        self.onEvent = onEvent
    }

    public var body: some View {
        render(view)
            .accessibilityLabel(view.accessibilityLabel ?? "")
    }

    private func render(_ view: YanxuMacUIView) -> AnyView {
        switch view.kind {
        case "Text":
            return AnyView(Text(view.text ?? "")
                .modifier(YanxuMacUIStyleModifier(style: view.style))
            )
        case "Button":
            return AnyView(Button(view.title ?? "Button") {
                if let event = view.event {
                    onEvent(event, ["source": view.stableID])
                }
            })
        case "TextField":
            return AnyView(TextField(view.placeholder ?? "", text: .constant(view.value?.stringValue ?? ""))
                .textFieldStyle(.roundedBorder)
                .disabled(view.disabled ?? false)
            )
        case "SecureField":
            return AnyView(SecureField(view.placeholder ?? "", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .disabled(view.disabled ?? false)
            )
        case "TextEditor":
            return AnyView(TextEditor(text: .constant(view.value?.stringValue ?? ""))
                .font(.body)
                .frame(minHeight: 120)
                .disabled(view.disabled ?? false)
            )
        case "Toggle":
            return AnyView(Toggle(view.title ?? "", isOn: .constant(view.value?.boolValue ?? false))
                .disabled(view.disabled ?? false)
            )
        case "Image":
            return AnyView(Image(systemName: view.systemName ?? "app")
                .imageScale(.large)
            )
        case "Spacer":
            return AnyView(Spacer(minLength: view.size.map { CGFloat($0) }))
        case "HStack":
            return AnyView(HStack(spacing: spacing(for: view)) {
                ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in
                    render(child)
                }
            }
            .modifier(YanxuMacUIStyleModifier(style: view.style)))
        case "VStack":
            return AnyView(VStack(alignment: .leading, spacing: spacing(for: view)) {
                ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in
                    render(child)
                }
            }
            .modifier(YanxuMacUIStyleModifier(style: view.style)))
        case "ScrollView":
            return AnyView(ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in
                        render(child)
                    }
                }
            })
        case "GroupBox":
            return AnyView(GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in
                        render(child)
                    }
                }
            })
        case "Form":
            return AnyView(Form {
                ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in
                    render(child)
                }
            })
        case "NavigationSplitView":
            let children = view.children ?? []
            return AnyView(NavigationSplitView {
                if children.indices.contains(0) { render(children[0]) }
            } content: {
                if children.indices.contains(1) { render(children[1]) }
            } detail: {
                if children.indices.contains(2) { render(children[2]) }
            })
        case "Divider":
            return AnyView(Divider())
        case "ProgressView":
            return AnyView(ProgressView(value: view.valueNumber))
        case "TabView":
            return AnyView(TabView {
                ForEach(Array((view.items ?? []).enumerated()), id: \.offset) { index, item in
                    Text(item.stringValue)
                        .tabItem { Text("Tab \(index + 1)") }
                }
            })
        case "List":
            return AnyView(List(Array((view.items ?? []).enumerated()), id: \.offset) { _, item in
                Text(item.stringValue)
            })
        default:
            return AnyView(Text("Unsupported view: \(view.kind)")
                .foregroundStyle(.secondary)
            )
        }
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
