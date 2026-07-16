import Foundation

public struct YanxuMacUIApplication: Decodable {
    public var schema: String
    public var name: String
    public var accentColor: String?
    public var windows: [YanxuMacUIWindow]
    public var menus: [YanxuMacUIMenuItem]?
    public var settings: YanxuMacUIView?
    public var documentBased: Bool?
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
    public var systemName: String? { properties["systemName"]?.optionalString }
    public var size: Double? { properties["size"]?.optionalNumber }
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

    fileprivate var optionalString: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    fileprivate var optionalNumber: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    fileprivate var optionalBool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    fileprivate var optionalArray: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    fileprivate var optionalObject: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}
