import AppKit
import Foundation

enum YanxuMacUIExportsV2 {
    private static let moduleName = copyCStringBytes("yanxu-macos-ui")
    private static let runName = copyCStringBytes("run")
    private static let updateName = copyCStringBytes("update")
    private static let patchName = copyCStringBytes("patch")
    private static let requestName = copyCStringBytes("request")
    private static let stopName = copyCStringBytes("stop")
    private static let validateName = copyCStringBytes("validate")

    private static var functionsStorage: [YanxuNativeFunctionV2] = [
        YanxuNativeFunctionV2(name: runName.0, nameLength: runName.1, context: nil as UnsafeMutableRawPointer?, call: yanxuMacUIRunV2),
        YanxuNativeFunctionV2(name: updateName.0, nameLength: updateName.1, context: nil as UnsafeMutableRawPointer?, call: yanxuMacUIUpdateV2),
        YanxuNativeFunctionV2(name: patchName.0, nameLength: patchName.1, context: nil as UnsafeMutableRawPointer?, call: yanxuMacUIPatchV2),
        YanxuNativeFunctionV2(name: requestName.0, nameLength: requestName.1, context: nil as UnsafeMutableRawPointer?, call: yanxuMacUIRequestV2),
        YanxuNativeFunctionV2(name: stopName.0, nameLength: stopName.1, context: nil as UnsafeMutableRawPointer?, call: yanxuMacUIStopV2),
        YanxuNativeFunctionV2(name: validateName.0, nameLength: validateName.1, context: nil as UnsafeMutableRawPointer?, call: yanxuMacUIValidateV2)
    ]

    private static var moduleStorage = YanxuNativeModuleV2(
        abiVersion: yanxuNativeABIVersionV2,
        structSize: MemoryLayout<YanxuNativeModuleV2>.size,
        name: moduleName.0,
        nameLength: moduleName.1,
        functions: functionsStorage.withUnsafeBufferPointer { $0.baseAddress },
        functionCount: functionsStorage.count,
        constants: nil,
        constantCount: 0,
        resourceTypes: nil,
        resourceTypeLengths: nil,
        resourceTypeCount: 0,
        freeValue: yanxuMacUIFreeValueV2,
        capabilities: 0
    )

    static var modulePointer: UnsafePointer<YanxuNativeModuleV2> {
        withUnsafePointer(to: &moduleStorage) { $0 }
    }
}

private func applicationJSON(
    _ arguments: UnsafeRawPointer?,
    _ count: Int,
    expectedCount: ClosedRange<Int> = 1...1,
    _ error: UnsafeMutableRawPointer?
) -> Data? {
    let typedError = error?.assumingMemoryBound(to: YanxuNativeErrorV2.self)
    let typedArguments = arguments?.assumingMemoryBound(to: YanxuNativeValueV2.self)
    guard expectedCount.contains(count),
          let typedArguments,
          let json = stringValueV2(typedArguments.pointee) else {
        setNativeErrorV2(typedError, code: "MACUI_ARGUMENT", message: "expected an application JSON string")
        return nil
    }
    return Data(json.utf8)
}

private let yanxuMacUIValidateV2: YanxuNativeFunctionCallV2 = { _, arguments, count, _, output, error in
    let typedOutput = output?.assumingMemoryBound(to: YanxuNativeValueV2.self)
    let typedError = error?.assumingMemoryBound(to: YanxuNativeErrorV2.self)
    guard let json = applicationJSON(arguments, count, error) else { return 1 }
    do {
        let app = try JSONDecoder().decode(YanxuMacUIApplication.self, from: json)
        try app.validate()
        setNullOutputV2(typedOutput)
        return yanxuNativeOK
    } catch {
        setNativeErrorV2(typedError, code: "MACUI_DECODE", message: String(describing: error))
        return 1
    }
}

private let yanxuMacUIPatchV2: YanxuNativeFunctionCallV2 = { _, arguments, count, _, output, error in
    let typedOutput = output?.assumingMemoryBound(to: YanxuNativeValueV2.self)
    let typedError = error?.assumingMemoryBound(to: YanxuNativeErrorV2.self)
    guard Thread.isMainThread else {
        setNativeErrorV2(typedError, code: "MACUI_THREAD", message: "patch must be called from the Yanxu owner/main thread")
        return 1
    }
    guard let json = applicationJSON(arguments, count, error) else { return 1 }
    do {
        try MainActor.assumeIsolated {
            guard let host = YanxuMacUIActiveApplication.host else {
                throw YanxuMacUIHostError.noRunningApplication
            }
            try host.patch(from: json)
        }
        setNullOutputV2(typedOutput)
        return yanxuNativeOK
    } catch {
        setNativeErrorV2(typedError, code: "MACUI_PATCH", message: String(describing: error))
        return 1
    }
}

private let yanxuMacUIRequestV2: YanxuNativeFunctionCallV2 = { _, arguments, count, _, output, error in
    let typedOutput = output?.assumingMemoryBound(to: YanxuNativeValueV2.self)
    let typedError = error?.assumingMemoryBound(to: YanxuNativeErrorV2.self)
    guard Thread.isMainThread else {
        setNativeErrorV2(typedError, code: "MACUI_THREAD", message: "request must be called from the Yanxu owner/main thread")
        return 1
    }
    guard let json = applicationJSON(arguments, count, error) else { return 1 }
    do {
        try MainActor.assumeIsolated {
            guard let host = YanxuMacUIActiveApplication.host else {
                throw YanxuMacUIHostError.noRunningApplication
            }
            try host.request(from: json)
        }
        setNullOutputV2(typedOutput)
        return yanxuNativeOK
    } catch {
        setNativeErrorV2(typedError, code: "MACUI_REQUEST", message: String(describing: error))
        return 1
    }
}

private let yanxuMacUIStopV2: YanxuNativeFunctionCallV2 = { _, _, count, _, output, error in
    let typedOutput = output?.assumingMemoryBound(to: YanxuNativeValueV2.self)
    let typedError = error?.assumingMemoryBound(to: YanxuNativeErrorV2.self)
    guard count == 0 else {
        setNativeErrorV2(typedError, code: "MACUI_ARGUMENT", message: "stop does not accept arguments")
        return 1
    }
    guard Thread.isMainThread else {
        setNativeErrorV2(typedError, code: "MACUI_THREAD", message: "stop must be called from the Yanxu owner/main thread")
        return 1
    }
    do {
        try MainActor.assumeIsolated {
            guard let host = YanxuMacUIActiveApplication.host else {
                throw YanxuMacUIHostError.noRunningApplication
            }
            host.stop()
        }
        setNullOutputV2(typedOutput)
        return yanxuNativeOK
    } catch {
        setNativeErrorV2(typedError, code: "MACUI_STOP", message: String(describing: error))
        return 1
    }
}

private let yanxuMacUIRunV2: YanxuNativeFunctionCallV2 = { _, arguments, count, nativeHost, output, error in
    let typedOutput = output?.assumingMemoryBound(to: YanxuNativeValueV2.self)
    let typedError = error?.assumingMemoryBound(to: YanxuNativeErrorV2.self)
    guard Thread.isMainThread else {
        setNativeErrorV2(typedError, code: "MACUI_THREAD", message: "run must be called from the Yanxu owner/main thread")
        return 1
    }
    guard let json = applicationJSON(arguments, count, expectedCount: 1...2, error) else { return 1 }
    let typedArguments = arguments?.assumingMemoryBound(to: YanxuNativeValueV2.self)
    var callback: YanxuMacUICallback?
    if count == 2 {
        guard let typedArguments,
              let created = YanxuMacUICallback(
                argument: typedArguments.advanced(by: 1).pointee,
                host: nativeHost?.assumingMemoryBound(to: YanxuNativeHostV2.self)
              ) else {
            setNativeErrorV2(typedError, code: "MACUI_CALLBACK", message: "run expects a Yanxu callback as its second argument")
            return 1
        }
        guard created.retain() else {
            setNativeErrorV2(typedError, code: "MACUI_CALLBACK", message: "could not retain the Yanxu event callback")
            return 1
        }
        callback = created
    }
    defer { callback?.release() }
    do {
        try MainActor.assumeIsolated {
            let typedHost = nativeHost?.assumingMemoryBound(to: YanxuNativeHostV2.self)
            let applicationHost = YanxuMacUIAppHost(
                terminateApplication: { NSApplication.shared.terminate(nil) },
                openExternalURL: { url in
                    yanxuNativeHostHasPermission(typedHost, "open_external_url")
                        && NSWorkspace.shared.open(url)
                }
            )
            try applicationHost.launch(from: json) { name, payload in
                if let callback {
                    if !callback.post(name: name, payload: payload) {
                        applicationHost.stop()
                    }
                } else {
                    NSLog("YanxuMacUI event %@ %@", name, String(describing: payload))
                }
            }
        }
        setNullOutputV2(typedOutput)
        return yanxuNativeOK
    } catch {
        setNativeErrorV2(typedError, code: "MACUI_LAUNCH", message: String(describing: error))
        return 1
    }
}

private let yanxuMacUIUpdateV2: YanxuNativeFunctionCallV2 = { _, arguments, count, _, output, error in
    let typedOutput = output?.assumingMemoryBound(to: YanxuNativeValueV2.self)
    let typedError = error?.assumingMemoryBound(to: YanxuNativeErrorV2.self)
    guard Thread.isMainThread else {
        setNativeErrorV2(typedError, code: "MACUI_THREAD", message: "update must be called from the Yanxu owner/main thread")
        return 1
    }
    guard let json = applicationJSON(arguments, count, error) else { return 1 }
    do {
        try MainActor.assumeIsolated {
            guard let host = YanxuMacUIActiveApplication.host else {
                throw YanxuMacUIHostError.noRunningApplication
            }
            try host.update(from: json)
        }
        setNullOutputV2(typedOutput)
        return yanxuNativeOK
    } catch {
        setNativeErrorV2(typedError, code: "MACUI_UPDATE", message: String(describing: error))
        return 1
    }
}

public func yanxuMacUIFreeValueV2(_ value: UnsafeMutableRawPointer?) {
    value?.assumingMemoryBound(to: YanxuNativeValueV2.self).pointee = YanxuNativeValueV2(kind: yanxuNativeValueNullV2, flags: 0, length: 0, data: 0)
}
