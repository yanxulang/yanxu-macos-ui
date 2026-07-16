import Foundation

final class YanxuMacUICallback {
    private let host: YanxuNativeHostV2
    private let handle: UInt64
    private var retained = false

    init?(argument: YanxuNativeValueV2, host: UnsafePointer<YanxuNativeHostV2>?) {
        guard argument.kind == yanxuNativeValueCallbackV2,
              let host,
              host.pointee.abiVersion == yanxuNativeABIVersionV2,
              host.pointee.structSize >= MemoryLayout<YanxuNativeHostV2>.size,
              host.pointee.callbackRetain != nil,
              host.pointee.callbackRelease != nil,
              host.pointee.callbackPost != nil,
              host.pointee.pump != nil else {
            return nil
        }
        self.host = host.pointee
        self.handle = argument.data
    }

    func retain() -> Bool {
        guard !retained, let pointer = host.callbackRetain else { return false }
        let function = unsafeBitCast(pointer, to: YanxuNativeCallbackRetainV2.self)
        retained = function(host.context, handle) == yanxuNativeOK
        return retained
    }

    func release() {
        guard retained, let pointer = host.callbackRelease else { return }
        let function = unsafeBitCast(pointer, to: YanxuNativeCallbackReleaseV2.self)
        _ = function(host.context, handle)
        retained = false
    }

    @discardableResult
    func post(name: String, payload: [String: JSONValue]) -> Bool {
        guard retained,
              let postPointer = host.callbackPost,
              let pumpPointer = host.pump else { return false }

        let arena = YanxuMacUIValueArena()
        let arguments = [arena.encode(.string(name)), arena.encode(.object(payload))]
        var error = YanxuNativeErrorV2(code: nil, codeLength: 0, message: nil, messageLength: 0)
        let post = unsafeBitCast(postPointer, to: YanxuNativeCallbackPostV2.self)
        let status = arguments.withUnsafeBufferPointer { buffer in
            withUnsafeMutablePointer(to: &error) { errorPointer in
                post(
                    host.context,
                    handle,
                    buffer.baseAddress.map(UnsafeRawPointer.init),
                    buffer.count,
                    UnsafeMutableRawPointer(errorPointer)
                )
            }
        }
        guard status == yanxuNativeOK else {
            NSLog("YanxuMacUI callback post failed: %@", nativeErrorMessage(error))
            return false
        }

        let pump = unsafeBitCast(pumpPointer, to: YanxuNativeHostPumpV2.self)
        let pumpStatus = withUnsafeMutablePointer(to: &error) { errorPointer in
            pump(host.context, 64, UnsafeMutableRawPointer(errorPointer))
        }
        if pumpStatus != yanxuNativeOK {
            NSLog("YanxuMacUI callback pump failed: %@", nativeErrorMessage(error))
            return false
        }
        return true
    }

    deinit {
        if retained {
            release()
        }
    }
}

private final class YanxuMacUIValueArena {
    private var byteBuffers: [UnsafeMutablePointer<UInt8>] = []
    private var valueBuffers: [(UnsafeMutablePointer<YanxuNativeValueV2>, Int)] = []

    func encode(_ value: JSONValue) -> YanxuNativeValueV2 {
        switch value {
        case .null:
            return YanxuNativeValueV2(kind: yanxuNativeValueNullV2, flags: 0, length: 0, data: 0)
        case .bool(let value):
            return YanxuNativeValueV2(
                kind: yanxuNativeValueBoolV2,
                flags: value ? yanxuNativeValueTrueFlagV2 : 0,
                length: 0,
                data: 0
            )
        case .number(let value):
            return YanxuNativeValueV2(
                kind: yanxuNativeValueNumberV2,
                flags: 0,
                length: 0,
                data: value.bitPattern
            )
        case .string(let value):
            let bytes = Array(value.utf8)
            guard !bytes.isEmpty else {
                return YanxuNativeValueV2(kind: yanxuNativeValueStringV2, flags: 0, length: 0, data: 0)
            }
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
            pointer.initialize(from: bytes, count: bytes.count)
            byteBuffers.append(pointer)
            return YanxuNativeValueV2(
                kind: yanxuNativeValueStringV2,
                flags: 0,
                length: UInt64(bytes.count),
                data: pointerBits(pointer)
            )
        case .array(let values):
            return encodeChildren(values.map(encode), kind: yanxuNativeValueArrayV2, logicalLength: values.count)
        case .object(let values):
            var children: [YanxuNativeValueV2] = []
            for key in values.keys.sorted() {
                children.append(encode(.string(key)))
                children.append(encode(values[key] ?? .null))
            }
            return encodeChildren(children, kind: yanxuNativeValueMapV2, logicalLength: values.count)
        }
    }

    private func encodeChildren(
        _ children: [YanxuNativeValueV2],
        kind: UInt32,
        logicalLength: Int
    ) -> YanxuNativeValueV2 {
        guard !children.isEmpty else {
            return YanxuNativeValueV2(kind: kind, flags: 0, length: UInt64(logicalLength), data: 0)
        }
        let pointer = UnsafeMutablePointer<YanxuNativeValueV2>.allocate(capacity: children.count)
        pointer.initialize(from: children, count: children.count)
        valueBuffers.append((pointer, children.count))
        return YanxuNativeValueV2(
            kind: kind,
            flags: 0,
            length: UInt64(logicalLength),
            data: pointerBits(pointer)
        )
    }

    deinit {
        for pointer in byteBuffers {
            pointer.deallocate()
        }
        for (pointer, count) in valueBuffers {
            pointer.deinitialize(count: count)
            pointer.deallocate()
        }
    }
}

private func pointerBits<T>(_ pointer: UnsafeMutablePointer<T>) -> UInt64 {
    UInt64(UInt(bitPattern: UnsafeRawPointer(pointer)))
}

private func nativeErrorMessage(_ error: YanxuNativeErrorV2) -> String {
    guard let pointer = error.message, error.messageLength > 0 else { return "unknown host error" }
    return String(bytes: UnsafeBufferPointer(start: pointer, count: error.messageLength), encoding: .utf8)
        ?? "invalid host error"
}
