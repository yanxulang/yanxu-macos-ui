import SwiftUI

extension YanxuMacUIRenderer {
    func renderPresentation(_ view: YanxuMacUIView) -> AnyView? {
        let children = view.children ?? []
        switch view.kind {
        case "Sheet":
            return AnyView(Group {
                if children.indices.contains(0) { render(children[0]) }
            }.sheet(isPresented: boolBinding(for: view)) {
                if children.indices.contains(1) { render(children[1]) }
            })
        case "Popover":
            return AnyView(Group {
                if children.indices.contains(0) { render(children[0]) }
            }.popover(isPresented: boolBinding(for: view)) {
                if children.indices.contains(1) { render(children[1]) }
            })
        case "Alert":
            return AnyView(Group {
                if children.indices.contains(0) { render(children[0]) }
            }.alert(view.title ?? "", isPresented: boolBinding(for: view)) {
                Button(view.dismissTitle ?? "OK", role: .cancel) {}
            } message: {
                Text(view.message ?? "")
            })
        case "Inspector":
            if #available(macOS 14.0, *) {
                return AnyView(Group {
                    if children.indices.contains(0) { render(children[0]) }
                }.inspector(isPresented: boolBinding(for: view)) {
                    if children.indices.contains(1) { render(children[1]) }
                })
            }
            return AnyView(HSplitView {
                if children.indices.contains(0) { render(children[0]) }
                if boolBinding(for: view).wrappedValue, children.indices.contains(1) {
                    render(children[1]).frame(minWidth: 180, idealWidth: 260)
                }
            })
        default: return nil
        }
    }
}
