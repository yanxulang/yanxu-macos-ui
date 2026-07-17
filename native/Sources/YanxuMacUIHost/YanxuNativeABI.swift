import Foundation

let yanxuNativeABIVersion: UInt32 = 1
let yanxuNativeOK: Int32 = 0
let yanxuNativeOutputJSON: UInt32 = 1
let yanxuNativeABIVersionV2: UInt32 = 2
let yanxuNativeValueNullV2: UInt32 = 0
let yanxuNativeValueBoolV2: UInt32 = 1
let yanxuNativeValueNumberV2: UInt32 = 3
let yanxuNativeValueStringV2: UInt32 = 4
let yanxuNativeValueArrayV2: UInt32 = 6
let yanxuNativeValueMapV2: UInt32 = 7
let yanxuNativeValueCallbackV2: UInt32 = 9
let yanxuNativeValueTrueFlagV2: UInt32 = 1

@_cdecl("yanxu_native_module_v1")
public func yanxuNativeModuleV1() -> UnsafeRawPointer {
    UnsafeRawPointer(YanxuMacUIExports.modulePointer)
}

@_cdecl("yanxu_native_module_v2")
public func yanxuNativeModuleV2() -> UnsafeRawPointer {
    UnsafeRawPointer(YanxuMacUIExportsV2.modulePointer)
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

public struct YanxuNativeValueV2 {
    public var kind: UInt32
    public var flags: UInt32
    public var length: UInt64
    public var data: UInt64
}

public struct YanxuNativeErrorV2 {
    public var code: UnsafePointer<UInt8>?
    public var codeLength: Int
    public var message: UnsafePointer<UInt8>?
    public var messageLength: Int
}

public struct YanxuNativeHostV2 {
    public var abiVersion: UInt32
    public var structSize: Int
    public var context: UnsafeMutableRawPointer?
    public var callbackRetain: UnsafeRawPointer?
    public var callbackRelease: UnsafeRawPointer?
    public var callbackPost: UnsafeRawPointer?
    public var wake: UnsafeRawPointer?
    public var pump: UnsafeRawPointer?
    public var hasPermission: UnsafeRawPointer?
    public var resourceGet: UnsafeRawPointer?
    public var eventLoopID: UInt64
    public var ownerThreadToken: UInt64
}

public typealias YanxuNativeCallbackRetainV2 = @convention(c) (
    UnsafeMutableRawPointer?,
    UInt64
) -> Int32

public typealias YanxuNativeCallbackReleaseV2 = @convention(c) (
    UnsafeMutableRawPointer?,
    UInt64
) -> Int32

public typealias YanxuNativeCallbackPostV2 = @convention(c) (
    UnsafeMutableRawPointer?,
    UInt64,
    UnsafeRawPointer?,
    Int,
    UnsafeMutableRawPointer?
) -> Int32

public typealias YanxuNativeHostPumpV2 = @convention(c) (
    UnsafeMutableRawPointer?,
    Int,
    UnsafeMutableRawPointer?
) -> Int32

public typealias YanxuNativeHostHasPermissionV2 = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<UInt8>?,
    Int
) -> Int32

func yanxuNativeHostHasPermission(_ host: UnsafePointer<YanxuNativeHostV2>?, _ capability: String) -> Bool {
    guard let host, let rawFunction = host.pointee.hasPermission else { return false }
    let function = unsafeBitCast(rawFunction, to: YanxuNativeHostHasPermissionV2.self)
    let bytes = Array(capability.utf8)
    return bytes.withUnsafeBufferPointer { buffer in
        function(host.pointee.context, buffer.baseAddress, buffer.count) == 1
    }
}

public typealias YanxuNativeFunctionCallV2 = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeRawPointer?,
    Int,
    UnsafeRawPointer?,
    UnsafeMutableRawPointer?,
    UnsafeMutableRawPointer?
) -> Int32

public struct YanxuNativeFunctionV2 {
    public var name: UnsafePointer<UInt8>?
    public var nameLength: Int
    public var context: UnsafeMutableRawPointer?
    public var call: YanxuNativeFunctionCallV2?
}

public struct YanxuNativeConstantV2 {
    public var name: UnsafePointer<UInt8>?
    public var nameLength: Int
    public var value: UnsafePointer<YanxuNativeValueV2>?
}

public struct YanxuNativeModuleV2 {
    public var abiVersion: UInt32
    public var structSize: Int
    public var name: UnsafePointer<UInt8>?
    public var nameLength: Int
    public var functions: UnsafePointer<YanxuNativeFunctionV2>?
    public var functionCount: Int
    public var constants: UnsafePointer<YanxuNativeConstantV2>?
    public var constantCount: Int
    public var resourceTypes: UnsafePointer<UnsafePointer<UInt8>?>?
    public var resourceTypeLengths: UnsafePointer<Int>?
    public var resourceTypeCount: Int
    public var freeValue: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
    public var capabilities: UInt64
}

func copyCStringBytes(_ string: String) -> (UnsafePointer<UInt8>, Int) {
    let bytes = Array(string.utf8)
    let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
    pointer.initialize(from: bytes, count: bytes.count)
    return (UnsafePointer(pointer), bytes.count)
}

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

func setNullOutputV2(_ output: UnsafeMutablePointer<YanxuNativeValueV2>?) {
    output?.pointee = YanxuNativeValueV2(kind: yanxuNativeValueNullV2, flags: 0, length: 0, data: 0)
}

func stringValueV2(_ value: YanxuNativeValueV2) -> String? {
    guard value.kind == yanxuNativeValueStringV2, value.length > 0 else { return nil }
    let pointer = UnsafeRawPointer(bitPattern: UInt(value.data))?.assumingMemoryBound(to: UInt8.self)
    guard let pointer else { return nil }
    let length = Int(value.length)
    return String(bytes: UnsafeBufferPointer(start: pointer, count: length), encoding: .utf8)
}

func setNativeErrorV2(_ error: UnsafeMutablePointer<YanxuNativeErrorV2>?, code: StaticString, message: String) {
    guard let error else { return }
    let codeBytes = copyCStringBytes(code.description)
    let messageBytes = copyCStringBytes(message)
    error.pointee = YanxuNativeErrorV2(
        code: codeBytes.0,
        codeLength: codeBytes.1,
        message: messageBytes.0,
        messageLength: messageBytes.1
    )
}
