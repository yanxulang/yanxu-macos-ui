import Foundation

let yanxuNativeABIVersion: UInt32 = 1
let yanxuNativeOK: Int32 = 0
let yanxuNativeOutputJSON: UInt32 = 1

@_cdecl("yanxu_native_module_v1")
public func yanxuNativeModuleV1() -> UnsafeRawPointer {
    UnsafeRawPointer(YanxuMacUIExports.modulePointer)
}

public struct YanxuNativeErrorV1 {
    public var code: UnsafePointer<UInt8>?
    public var codeLength: Int
    public var message: UnsafePointer<UInt8>?
    public var messageLength: Int
}

public struct YanxuNativeOutputV1 {
    public var kind: UInt32
    public var json: UnsafeMutablePointer<UInt8>?
    public var jsonLength: Int
    public var resource: UnsafeMutableRawPointer?
    public var resourceType: UnsafePointer<UInt8>?
    public var resourceTypeLength: Int
    public var dropResource: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
}

public typealias YanxuNativeFunctionCall = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<UInt8>?,
    Int,
    UnsafeRawPointer?,
    UnsafeMutableRawPointer?,
    UnsafeMutableRawPointer?
) -> Int32

public struct YanxuNativeFunctionV1 {
    public var name: UnsafePointer<UInt8>?
    public var nameLength: Int
    public var context: UnsafeMutableRawPointer?
    public var call: YanxuNativeFunctionCall?
}

public struct YanxuNativeConstantV1 {
    public var name: UnsafePointer<UInt8>?
    public var nameLength: Int
    public var valueJSON: UnsafePointer<UInt8>?
    public var valueJSONLength: Int
}

public struct YanxuNativeModuleV1 {
    public var abiVersion: UInt32
    public var structSize: Int
    public var name: UnsafePointer<UInt8>?
    public var nameLength: Int
    public var functions: UnsafePointer<YanxuNativeFunctionV1>?
    public var functionCount: Int
    public var constants: UnsafePointer<YanxuNativeConstantV1>?
    public var constantCount: Int
    public var resourceTypes: UnsafePointer<UnsafePointer<UInt8>?>?
    public var resourceTypeLengths: UnsafePointer<Int>?
    public var resourceTypeCount: Int
    public var freeBytes: (@convention(c) (UnsafeMutablePointer<UInt8>?, Int) -> Void)?
    public var capabilities: UInt64
}

func copyCStringBytes(_ string: String) -> (UnsafePointer<UInt8>, Int) {
    let bytes = Array(string.utf8)
    let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
    pointer.initialize(from: bytes, count: bytes.count)
    return (UnsafePointer(pointer), bytes.count)
}

@_cdecl("yanxu_macui_free_bytes")
public func yanxuMacUIFreeBytes(_ pointer: UnsafeMutablePointer<UInt8>?, _ length: Int) {
    pointer?.deallocate()
}

func setJSONOutput(_ value: Any, output: UnsafeMutablePointer<YanxuNativeOutputV1>?) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
    data.copyBytes(to: pointer, count: data.count)
    output?.pointee = YanxuNativeOutputV1(
        kind: yanxuNativeOutputJSON,
        json: pointer,
        jsonLength: data.count,
        resource: nil,
        resourceType: nil,
        resourceTypeLength: 0,
        dropResource: nil
    )
}
