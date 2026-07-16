import SwiftUI

extension YanxuMacUIRenderer {
    func decorate(_ content: AnyView, with view: YanxuMacUIView) -> AnyView {
        var result = AnyView(content
            .disabled(view.disabled ?? false)
            .modifier(YanxuMacUIStyleModifier(style: view.style)))
        if let frame = view.properties["frame"]?.optionalObject,
           let width = frame["width"]?.optionalNumber,
           let height = frame["height"]?.optionalNumber {
            result = AnyView(result.frame(width: width, height: height))
        }
        if let help = view.help { result = AnyView(result.help(help)) }
        if let label = view.accessibilityLabel { result = AnyView(result.accessibilityLabel(label)) }
        if let binding = view.focusBinding {
            result = AnyView(result.modifier(YanxuMacUIFocusModifier(
                identifier: view.stableID,
                binding: binding,
                store: store,
                onEvent: onEvent
            )))
        }
        return result
    }
}

private struct YanxuMacUIFocusModifier: ViewModifier {
    let identifier: String
    let binding: String
    @ObservedObject var store: YanxuMacUIApplicationStore
    let onEvent: YanxuMacUIEventHandler
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        let requestedFocus = store.value(for: binding, fallback: .string("")).stringValue == identifier
        content
            .focused($focused)
            .onAppear { focused = requestedFocus }
            .onChange(of: requestedFocus) { focused = $0 }
            .onChange(of: focused) { isFocused in
                let current = store.value(for: binding, fallback: .string("")).stringValue
                guard isFocused || current == identifier else { return }
                let value = JSONValue.string(isFocused ? identifier : "")
                store.setValue(value, forBinding: binding)
                onEvent("focus.changed", [
                    "source": .string(identifier),
                    "binding": .string(binding),
                    "value": value,
                    "revision": .number(Double(store.application.revision ?? 0))
                ])
            }
    }
}

private struct YanxuMacUIStyleModifier: ViewModifier {
    var style: [String: JSONValue]?

    func body(content: Content) -> some View {
        var result = AnyView(content)
        if case .number(let padding) = style?["padding"] { result = AnyView(result.padding(padding)) }
        if case .string(let weight) = style?["weight"], weight == "semibold" {
            result = AnyView(result.fontWeight(.semibold))
        }
        if case .string(let font) = style?["font"] { result = AnyView(result.font(fontValue(font))) }
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
