import Foundation

enum YanxuMacUIExports {
    private static let moduleName = copyCStringBytes("YanxuMacUIHost")
    private static let launchName = copyCStringBytes("launch")
    private static let validateName = copyCStringBytes("validate")
    private static let versionName = copyCStringBytes("version")
    private static let versionValue = copyCStringBytes("\"0.8.8\"")

    private static var functionsStorage: [YanxuNativeFunctionV1] = [
        YanxuNativeFunctionV1(name: launchName.0, nameLength: launchName.1, context: nil as UnsafeMutableRawPointer?, call: yanxuMacUILaunch),
        YanxuNativeFunctionV1(name: validateName.0, nameLength: validateName.1, context: nil as UnsafeMutableRawPointer?, call: yanxuMacUIValidate)
    ]

    private static var constantsStorage: [YanxuNativeConstantV1] = [
        YanxuNativeConstantV1(name: versionName.0, nameLength: versionName.1, valueJSON: versionValue.0, valueJSONLength: versionValue.1)
    ]

    private static var moduleStorage = YanxuNativeModuleV1(
        abiVersion: yanxuNativeABIVersion,
        structSize: MemoryLayout<YanxuNativeModuleV1>.size,
        name: moduleName.0,
        nameLength: moduleName.1,
        functions: functionsStorage.withUnsafeBufferPointer { $0.baseAddress },
        functionCount: functionsStorage.count,
        constants: constantsStorage.withUnsafeBufferPointer { $0.baseAddress },
        constantCount: constantsStorage.count,
        resourceTypes: nil,
        resourceTypeLengths: nil,
        resourceTypeCount: 0,
        freeBytes: yanxuMacUIFreeBytes,
        capabilities: 0
    )

    static var modulePointer: UnsafePointer<YanxuNativeModuleV1> {
        withUnsafePointer(to: &moduleStorage) { $0 }
    }
}

private func inputData(_ input: UnsafePointer<UInt8>?, _ length: Int) -> Data {
    guard let input, length > 0 else { return Data() }
    return Data(bytes: input, count: length)
}

private func decodeEnvelope(_ input: UnsafePointer<UInt8>?, _ length: Int) throws -> Data {
    let data = inputData(input, length)
    guard !data.isEmpty else { throw YanxuMacUIHostError.invalidSchema("") }
    if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
       let json = object["json"] as? String {
        return Data(json.utf8)
    }
    return data
}

private let yanxuMacUIValidate: YanxuNativeFunctionCall = { _, input, length, _, output, _ in
    let typedOutput = output?.assumingMemoryBound(to: YanxuNativeOutputV1.self)
    do {
        let json = try decodeEnvelope(input, length)
        let app = try JSONDecoder().decode(YanxuMacUIApplication.self, from: json)
        try app.validate()
        try setJSONOutput([
            "ok": true,
            "schema": app.schema,
            "windows": app.windows.count
        ], output: typedOutput)
        return yanxuNativeOK
    } catch {
        try? setJSONOutput(["ok": false, "error": String(describing: error)], output: typedOutput)
        return yanxuNativeOK
    }
}

private let yanxuMacUILaunch: YanxuNativeFunctionCall = { _, input, length, _, output, _ in
    let typedOutput = output?.assumingMemoryBound(to: YanxuNativeOutputV1.self)
    do {
        let json = try decodeEnvelope(input, length)
        DispatchQueue.main.async {
            let host = YanxuMacUIAppHost()
            try? host.launch(from: json) { name, payload in
                NSLog("YanxuMacUI event %@ %@", name, payload)
            }
        }
        try setJSONOutput(["ok": true], output: typedOutput)
        return yanxuNativeOK
    } catch {
        try? setJSONOutput(["ok": false, "error": String(describing: error)], output: typedOutput)
        return yanxuNativeOK
    }
}
