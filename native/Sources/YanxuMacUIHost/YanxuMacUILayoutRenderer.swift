import SwiftUI

extension YanxuMacUIRenderer {
    func renderLayout(_ view: YanxuMacUIView) -> AnyView? {
        switch view.kind {
        case "HStack":
            return AnyView(HStack(spacing: spacing(for: view)) {
                ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in render(child) }
            })
        case "VStack":
            return AnyView(VStack(alignment: .leading, spacing: spacing(for: view)) {
                ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in render(child) }
            })
        case "ScrollView":
            return AnyView(ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in render(child) }
                }
            })
        case "GroupBox":
            return AnyView(GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in render(child) }
                }
            })
        case "Form":
            return AnyView(Form {
                ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in render(child) }
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
        case "Search":
            let children = view.children ?? []
            return AnyView(Group {
                if children.indices.contains(0) { render(children[0]) }
            }.searchable(text: textBinding(for: view), prompt: view.placeholder ?? "Search"))
        default: return nil
        }
    }

    private func spacing(for view: YanxuMacUIView) -> Double {
        if case .number(let value) = view.style?["spacing"] { return value }
        return 8
    }
}
