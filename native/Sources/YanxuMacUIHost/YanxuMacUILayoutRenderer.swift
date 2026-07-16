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
        case "ControlGroup":
            return AnyView(ControlGroup {
                ForEach(Array((view.children ?? []).enumerated()), id: \.offset) { _, child in render(child) }
            })
        case "DisclosureGroup":
            return AnyView(DisclosureGroup(view.title ?? "", isExpanded: boolBinding(for: view)) {
                if let content = view.children?.first { render(content) }
            })
        case "NavigationStack":
            let destinations = view.children ?? []
            return AnyView(NavigationStack(path: navigationPathBinding(for: view)) {
                List(destinations, id: \.stableID) { destination in
                    NavigationLink(value: destination.stableID) {
                        Text(destination.title ?? destination.stableID)
                    }
                }
                .navigationDestination(for: String.self) { identifier in
                    if let destination = destinations.first(where: { $0.stableID == identifier }),
                       let content = destination.children?.first {
                        render(content)
                            .navigationTitle(destination.title ?? "")
                    } else {
                        Text("Unavailable destination")
                    }
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

    private func navigationPathBinding(for view: YanxuMacUIView) -> Binding<[String]> {
        Binding(
            get: {
                store.value(for: view, fallback: .array([])).optionalArray?.map(\.stringValue) ?? []
            },
            set: { path in
                let value = JSONValue.array(path.map(JSONValue.string))
                store.setValue(value, for: view)
                emitChange(for: view, value: value)
            }
        )
    }
}
