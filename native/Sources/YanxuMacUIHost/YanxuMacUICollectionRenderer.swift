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
        case "Table":
            return AnyView(YanxuMacUIDynamicTable(
                columns: tableColumns(for: view),
                rows: tableRows(for: view, sortKey: view.properties["sortKey"]?.optionalString),
                selection: selectionBinding(for: view)
            ))
        case "Outline":
            return AnyView(List {
                OutlineGroup(outlineNodes(for: view), children: \.children) { node in
                    Label(node.title, systemImage: node.systemName ?? "doc")
                }
            })
        default: return nil
        }
    }

    func selectionBinding(for view: YanxuMacUIView) -> Binding<Set<String>> {
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

    private func tableColumns(for view: YanxuMacUIView) -> [YanxuMacUITableColumn] {
        (view.properties["columns"]?.optionalArray ?? []).compactMap { value in
            guard let item = value.optionalObject,
                  let title = item["title"]?.optionalString,
                  let key = item["key"]?.optionalString else { return nil }
            return YanxuMacUITableColumn(title: title, key: key, width: item["width"]?.optionalNumber)
        }
    }

    private func tableRows(for view: YanxuMacUIView, sortKey: String?) -> [YanxuMacUITableRow] {
        (view.items ?? []).enumerated().compactMap { index, value in
            guard let item = value.optionalObject else { return nil }
            let key = sortKey ?? tableColumns(for: view).first?.key ?? "id"
            return YanxuMacUITableRow(
                id: item["id"]?.stringValue ?? "row-\(index)",
                sortValue: item[key]?.stringValue ?? "",
                values: item
            )
        }
    }

    private func outlineNodes(for view: YanxuMacUIView) -> [YanxuMacUIOutlineNode] {
        (view.items ?? []).enumerated().compactMap { YanxuMacUIOutlineNode(value: $0.element, fallbackID: "node-\($0.offset)") }
    }
}

private struct YanxuMacUITableColumn: Identifiable {
    var id: String { key }
    let title: String
    let key: String
    let width: Double?
}

private struct YanxuMacUITableRow: Identifiable {
    let id: String
    let sortValue: String
    let values: [String: JSONValue]
}

private struct YanxuMacUIDynamicTable: View {
    let columns: [YanxuMacUITableColumn]
    let rows: [YanxuMacUITableRow]
    @Binding var selection: Set<String>
    @State private var sortOrder = [KeyPathComparator(\YanxuMacUITableRow.sortValue)]

    private var sortedRows: [YanxuMacUITableRow] {
        rows.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(columns.map(\.title).joined(separator: "    "), value: \.sortValue) { row in
                HStack(spacing: 12) {
                    ForEach(columns) { column in
                        Text(row.values[column.key]?.stringValue ?? "")
                            .frame(minWidth: 60, idealWidth: column.width ?? 140, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct YanxuMacUIOutlineNode: Identifiable {
    let id: String
    let title: String
    let systemName: String?
    let children: [YanxuMacUIOutlineNode]?

    init?(value: JSONValue, fallbackID: String) {
        guard let item = value.optionalObject else { return nil }
        let nodeID = item["id"]?.stringValue ?? fallbackID
        id = nodeID
        title = item["title"]?.stringValue ?? nodeID
        systemName = item["systemName"]?.optionalString
        let nested = item["children"]?.optionalArray ?? []
        children = nested.isEmpty ? nil : nested.enumerated().compactMap {
            YanxuMacUIOutlineNode(value: $0.element, fallbackID: "\(nodeID)-\($0.offset)")
        }
    }
}
