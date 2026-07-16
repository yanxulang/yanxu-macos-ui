import SwiftUI

extension YanxuMacUIRenderer {
    func renderCollection(_ view: YanxuMacUIView) -> AnyView? {
        switch view.kind {
        case "TabView":
            return AnyView(TabView {
                ForEach(Array((view.items ?? []).enumerated()), id: \.offset) { index, item in
                    Text(item.stringValue).tabItem { Text("Tab \(index + 1)") }
                }
            })
        case "List" where view.binding != nil:
            return AnyView(List(selection: selectionBinding(for: view)) {
                ForEach(options(for: view), id: \.value) { option in Text(option.title).tag(option.value) }
            })
        case "List":
            return AnyView(List(Array((view.items ?? []).enumerated()), id: \.offset) { _, item in
                Text(item.stringValue)
            })
        default: return nil
        }
    }

    private func selectionBinding(for view: YanxuMacUIView) -> Binding<Set<String>> {
        Binding(
            get: {
                let value = store.value(for: view, fallback: .array([]))
                return Set(value.optionalArray?.map(\.stringValue) ?? [])
            },
            set: { selection in
                let value = JSONValue.array(selection.sorted().map(JSONValue.string))
                store.setValue(value, for: view)
                emitChange(for: view, value: value)
            }
        )
    }
}
