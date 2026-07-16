import Foundation

public struct YanxuMacUIApplication: Decodable {
    public var schema: String
    public var revision: Int?
    public var state: [YanxuMacUIState]?
    public var name: String
    public var accentColor: String?
    public var windows: [YanxuMacUIWindow]
    public var menus: [YanxuMacUIMenuItem]?
    public var menuBarItems: [YanxuMacUIMenuBarItem]?
    public var settings: YanxuMacUIView?
    public var documentBased: Bool?
}

public struct YanxuMacUIMenuBarItem: Decodable {
    public var id: String
    public var systemName: String
    public var tooltip: String
    public var size: YanxuMacUISize
    public var content: YanxuMacUIView
}

public struct YanxuMacUIState: Decodable, Equatable {
    public var id: String
    public var type: String
    public var value: JSONValue
}

public struct YanxuMacUIStatePatch: Decodable {
    public var schema: String
    public var revision: Int
    public var state: [YanxuMacUIState]
}

public struct YanxuMacUIWindow: Decodable {
    public var title: String
    public var size: YanxuMacUISize?
    public var minSize: YanxuMacUISize?
    public var resizable: Bool?
    public var toolbar: [YanxuMacUIToolbarItem]?
    public var root: YanxuMacUIView
}

public struct YanxuMacUISize: Decodable {
    public var width: Double
    public var height: Double
}

public struct YanxuMacUIMenuItem: Decodable {
    public var title: String
    public var event: String?
    public var items: [YanxuMacUICommand]?
}

public struct YanxuMacUICommand: Decodable {
    public var title: String
    public var event: String
    public var shortcut: YanxuMacUIShortcut?
    public var role: String?
}

public struct YanxuMacUIShortcut: Decodable {
    public var key: String
    public var modifiers: [String]
}

public struct YanxuMacUIToolbarItem: Decodable {
    public var id: String
    public var title: String
    public var event: String
}

public struct YanxuMacUIView: Decodable, Identifiable {
    public var kind: String
    public var children: [YanxuMacUIView]?
    public var properties: [String: JSONValue]

    public var id: String? { properties["id"]?.optionalString }
    public var text: String? { properties["text"]?.optionalString }
    public var title: String? { properties["title"]?.optionalString }
    public var placeholder: String? { properties["placeholder"]?.optionalString }
    public var value: JSONValue? { properties["value"] }
    public var event: String? { properties["event"]?.optionalString }
    public var binding: String? { properties["binding"]?.optionalString }
    public var bindingType: String? { properties["bindingType"]?.optionalString }
    public var systemName: String? { properties["systemName"]?.optionalString }
    public var size: Double? { properties["size"]?.optionalNumber }
    public var minimum: Double? { properties["minimum"]?.optionalNumber }
    public var maximum: Double? { properties["maximum"]?.optionalNumber }
    public var step: Double? { properties["step"]?.optionalNumber }
    public var url: String? { properties["url"]?.optionalString }
    public var message: String? { properties["message"]?.optionalString }
    public var dismissTitle: String? { properties["dismissTitle"]?.optionalString }
    public var items: [JSONValue]? { properties["items"]?.optionalArray }
    public var disabled: Bool? { properties["disabled"]?.optionalBool }
    public var help: String? { properties["help"]?.optionalString }
    public var style: [String: JSONValue]? { properties["style"]?.optionalObject }
    public var accessibilityLabel: String? { properties["accessibilityLabel"]?.optionalString }

    public var stableID: String {
        id ?? "\(kind)-\(title ?? text ?? systemName ?? "view")"
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        guard let kindKey = DynamicKey(stringValue: "kind") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "invalid kind key"))
        }
        kind = try container.decode(String.self, forKey: kindKey)
        if let childrenKey = DynamicKey(stringValue: "children") {
            children = try container.decodeIfPresent([YanxuMacUIView].self, forKey: childrenKey)
        } else {
            children = nil
        }
        var decoded: [String: JSONValue] = [:]
        for key in container.allKeys where key.stringValue != "kind" && key.stringValue != "children" {
            decoded[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        properties = decoded
    }
}

extension YanxuMacUIApplication {
    func validate() throws {
        guard schema == "dev.yanxu.mac-ui.v1" || schema == "dev.yanxu.mac-ui.v2" else {
            throw YanxuMacUIHostError.invalidSchema(schema)
        }
        guard !windows.isEmpty || !(menuBarItems ?? []).isEmpty else {
            throw YanxuMacUIHostError.noPresentationAnchor
        }
        if schema == "dev.yanxu.mac-ui.v1" { return }
        guard let revision, revision >= 0 else { throw YanxuMacUIHostError.invalidRevision }

        var states: [String: YanxuMacUIState] = [:]
        for item in state ?? [] {
            guard item.id.isYanxuMacUIIdentifier else {
                throw YanxuMacUIHostError.invalidIdentifier("state", item.id)
            }
            guard states[item.id] == nil else {
                throw YanxuMacUIHostError.duplicateIdentifier("state", item.id)
            }
            guard item.value.matches(stateType: item.type) else {
                throw YanxuMacUIHostError.invalidStateType(item.id, item.type)
            }
            states[item.id] = item
        }
        var viewIDs = Set<String>()
        for window in windows {
            try window.root.validate(states: states, viewIDs: &viewIDs)
        }
        var menuBarIDs = Set<String>()
        for item in menuBarItems ?? [] {
            guard item.id.isYanxuMacUIIdentifier else {
                throw YanxuMacUIHostError.invalidIdentifier("menu bar item", item.id)
            }
            guard menuBarIDs.insert(item.id).inserted else {
                throw YanxuMacUIHostError.duplicateIdentifier("menu bar item", item.id)
            }
            guard !item.systemName.isEmpty, !item.tooltip.isEmpty,
                  item.size.width >= 160, item.size.height >= 120 else {
                throw YanxuMacUIHostError.invalidMenuBarItem(item.id)
            }
            try item.content.validate(states: states, viewIDs: &viewIDs)
        }
    }
}

private extension YanxuMacUIView {
    func validate(states: [String: YanxuMacUIState], viewIDs: inout Set<String>) throws {
        if let id {
            guard id.isYanxuMacUIIdentifier else {
                throw YanxuMacUIHostError.invalidIdentifier("view", id)
            }
            guard viewIDs.insert(id).inserted else {
                throw YanxuMacUIHostError.duplicateIdentifier("view", id)
            }
        }
        if let binding {
            let identityOptionalKinds: Set<String> = ["Text"]
            guard id != nil || identityOptionalKinds.contains(kind) else {
                throw YanxuMacUIHostError.boundViewNeedsIdentifier(kind)
            }
            guard let state = states[binding] else { throw YanxuMacUIHostError.unknownBinding(binding) }
            guard bindingType == state.type else {
                throw YanxuMacUIHostError.bindingTypeMismatch(binding, bindingType ?? "missing", state.type)
            }
            let expectedTypes: [String: String] = [
                "Text": "string", "TextField": "string", "SecureField": "string",
                "TextEditor": "string", "SearchField": "string", "Search": "string",
                "Picker": "string", "DatePicker": "string", "ColorPicker": "string",
                "Toggle": "bool", "Sheet": "bool", "Popover": "bool", "Alert": "bool",
                "Slider": "number", "Stepper": "number", "ProgressView": "number",
                "List": "selection"
            ]
            guard expectedTypes[kind] == state.type else {
                throw YanxuMacUIHostError.unsupportedBindingType(kind, state.type)
            }
        }
        if kind == "Slider" || kind == "Stepper" {
            guard let minimum, let maximum, let step,
                  minimum < maximum, step > 0 else {
                throw YanxuMacUIHostError.invalidControlConfiguration(kind)
            }
        }
        for child in children ?? [] {
            try child.validate(states: states, viewIDs: &viewIDs)
        }
    }
}

extension String {
    var isYanxuMacUIIdentifier: Bool {
        range(of: #"^[A-Za-z_][A-Za-z0-9_.:-]*$"#, options: .regularExpression) != nil
    }
}

public enum JSONValue: Decodable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public var stringValue: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): value ? "true" : "false"
        case .object, .array: ""
        case .null: ""
        }
    }

    public var boolValue: Bool {
        if case .bool(let value) = self { return value }
        return false
    }

    public var numberValue: Double {
        if case .number(let value) = self { return value }
        return 0
    }

    func matches(stateType: String) -> Bool {
        switch (stateType, self) {
        case ("string", .string), ("number", .number), ("bool", .bool), ("selection", .array): true
        default: false
        }
    }

    var optionalString: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var optionalNumber: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var optionalBool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var optionalArray: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var optionalObject: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}
