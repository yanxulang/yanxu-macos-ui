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
        return result
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
