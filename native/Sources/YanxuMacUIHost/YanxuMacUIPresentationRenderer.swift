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
        default: return nil
        }
    }
}
