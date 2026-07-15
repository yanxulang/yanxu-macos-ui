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
    public var id: String?
    public var kind: String
    public var children: [YanxuMacUIView]?
    public var text: String?
    public var title: String?
    public var placeholder: String?
    public var value: JSONValue?
    public var event: String?
    public var systemName: String?
    public var size: Double?
    public var items: [JSONValue]?
    public var disabled: Bool?
    public var help: String?
    public var style: [String: JSONValue]?
    public var accessibilityLabel: String?

    public var stableID: String {
        id ?? "\(kind)-\(title ?? text ?? systemName ?? "view")"
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
}
