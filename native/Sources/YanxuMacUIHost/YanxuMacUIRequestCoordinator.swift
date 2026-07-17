import AppKit
import Foundation
import Security
import UniformTypeIdentifiers

struct YanxuMacUIRequest: Decodable {
    let id: String
    let type: String
    let windowID: String?
    let sceneID: String?
    let title: String?
    let allowedTypes: [String]?
    let allowsMultiple: Bool?
    let suggestedName: String?
    let content: String?
    let encoding: String?
    let service: String?
    let account: String?
    let value: String?
    let interval: Double?
    let timerID: String?

    init(
        id: String,
        type: String,
        windowID: String? = nil,
        sceneID: String? = nil,
        title: String? = nil,
        allowedTypes: [String]? = nil,
        allowsMultiple: Bool? = nil,
        suggestedName: String? = nil,
        content: String? = nil,
        encoding: String? = nil,
        service: String? = nil,
        account: String? = nil,
        value: String? = nil,
        interval: Double? = nil,
        timerID: String? = nil
    ) {
        self.id = id
        self.type = type
        self.windowID = windowID
        self.sceneID = sceneID
        self.title = title
        self.allowedTypes = allowedTypes
        self.allowsMultiple = allowsMultiple
        self.suggestedName = suggestedName
        self.content = content
        self.encoding = encoding
        self.service = service
        self.account = account
        self.value = value
        self.interval = interval
        self.timerID = timerID
    }
}

@MainActor
final class YanxuMacUIRequestCoordinator {
    private let onEvent: YanxuMacUIEventHandler
    private let openWindow: (String) -> Bool
    private let closeWindow: (String) -> Bool
    private let openSettings: () -> Bool
    private let openDocument: (String, String?, [String: JSONValue]?) -> String?
    private var timers: [String: Timer] = [:]

    deinit {
        timers.values.forEach { $0.invalidate() }
    }

    init(
        onEvent: @escaping YanxuMacUIEventHandler,
        openWindow: @escaping (String) -> Bool,
        closeWindow: @escaping (String) -> Bool,
        openSettings: @escaping () -> Bool,
        openDocument: @escaping (String, String?, [String: JSONValue]?) -> String?
    ) {
        self.onEvent = onEvent
        self.openWindow = openWindow
        self.closeWindow = closeWindow
        self.openSettings = openSettings
        self.openDocument = openDocument
    }

    func perform(_ request: YanxuMacUIRequest) throws {
        guard request.id.isYanxuMacUIIdentifier else {
            throw YanxuMacUIHostError.invalidIdentifier("request", request.id)
        }
        switch request.type {
        case "window.open":
            complete(request, result: ["opened": .bool(request.windowID.map(openWindow) ?? false)])
        case "window.close":
            complete(request, result: ["closed": .bool(request.windowID.map(closeWindow) ?? false)])
        case "settings.open":
            complete(request, result: ["opened": .bool(openSettings())])
        case "document.new":
            let identifier = request.sceneID.flatMap { openDocument($0, request.suggestedName, nil) }
            complete(request, result: ["document": identifier.map(JSONValue.string) ?? .null])
        case "file.open", "file.import", "document.open":
            presentOpenPanel(for: request)
        case "file.save", "file.export", "document.save":
            presentSavePanel(for: request)
        case "secure.get", "secure.set", "secure.delete":
            performSecureStorageRequest(request)
        case "timer.start":
            startTimer(request)
        case "timer.stop":
            stopTimer(request)
        default:
            throw YanxuMacUIHostError.unsupportedRequest(request.type)
        }
    }

    private func performSecureStorageRequest(_ request: YanxuMacUIRequest) {
        guard let service = request.service, !service.isEmpty,
              let account = request.account, !account.isEmpty else {
            fail(request, message: "secure storage requires service and account")
            return
        }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        switch request.type {
        case "secure.get":
            var query = identity
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var raw: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &raw)
            if status == errSecItemNotFound {
                complete(request, result: ["found": .bool(false), "value": .string("")])
            } else if status == errSecSuccess, let data = raw as? Data {
                complete(request, result: ["found": .bool(true), "value": .string(String(decoding: data, as: UTF8.self))])
            } else {
                fail(request, message: "secure storage read failed (\(status))")
            }
        case "secure.set":
            SecItemDelete(identity as CFDictionary)
            var item = identity
            item[kSecValueData as String] = Data((request.value ?? "").utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(item as CFDictionary, nil)
            status == errSecSuccess
                ? complete(request, result: ["stored": .bool(true)])
                : fail(request, message: "secure storage write failed (\(status))")
        case "secure.delete":
            let status = SecItemDelete(identity as CFDictionary)
            if status == errSecSuccess || status == errSecItemNotFound {
                complete(request, result: ["deleted": .bool(status == errSecSuccess)])
            } else {
                fail(request, message: "secure storage delete failed (\(status))")
            }
        default:
            break
        }
    }

    private func startTimer(_ request: YanxuMacUIRequest) {
        guard let interval = request.interval, interval >= 1 else {
            fail(request, message: "timer interval must be at least one second")
            return
        }
        timers[request.id]?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onEvent("timer.fired", ["timer": .string(request.id)])
            }
        }
        timers[request.id] = timer
        RunLoop.main.add(timer, forMode: .common)
        complete(request, result: ["started": .bool(true), "interval": .number(interval)])
    }

    private func stopTimer(_ request: YanxuMacUIRequest) {
        let timerID = request.timerID ?? request.id
        let existed = timers.removeValue(forKey: timerID)
        existed?.invalidate()
        complete(request, result: ["stopped": .bool(existed != nil), "timer": .string(timerID)])
    }

    private func presentOpenPanel(for request: YanxuMacUIRequest) {
        let panel = NSOpenPanel()
        panel.title = request.title ?? (request.type == "file.import" ? "Import" : "Open")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = request.allowsMultiple ?? false
        panel.allowedContentTypes = contentTypes(request.allowedTypes)
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK else {
                self.complete(request, cancelled: true)
                return
            }
            do {
                let files = try panel.urls.map { try self.readFile($0, encoding: request.encoding) }
                var result: [String: JSONValue] = ["files": .array(files.map(JSONValue.object))]
                if request.type == "document.open" {
                    let documents = files.compactMap { file in
                        request.sceneID.flatMap { self.openDocument($0, file["name"]?.optionalString, file) }
                    }
                    result["documents"] = .array(documents.map(JSONValue.string))
                    self.onEvent("document.opened", [
                        "request": .string(request.id),
                        "scene": .string(request.sceneID ?? ""),
                        "files": .array(files.map(JSONValue.object))
                    ])
                }
                self.complete(request, result: result)
            } catch {
                self.fail(request, error: error)
            }
        }
    }

    private func presentSavePanel(for request: YanxuMacUIRequest) {
        let panel = NSSavePanel()
        panel.title = request.title ?? (request.type == "file.export" ? "Export" : "Save")
        panel.nameFieldStringValue = request.suggestedName ?? "Untitled.txt"
        panel.allowedContentTypes = contentTypes(request.allowedTypes)
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                self.complete(request, cancelled: true)
                return
            }
            do {
                try self.writeFile(url, content: request.content ?? "", encoding: request.encoding)
                let result = self.urlDescription(url)
                self.complete(request, result: result)
                if request.type == "document.save" {
                    self.onEvent("document.saved", [
                        "request": .string(request.id),
                        "scene": .string(request.sceneID ?? ""),
                        "document": .string(request.windowID ?? ""),
                        "file": .object(result)
                    ])
                }
            } catch {
                self.fail(request, error: error)
            }
        }
    }

    private func readFile(_ url: URL, encoding: String?) throws -> [String: JSONValue] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= 16 * 1024 * 1024 else { throw YanxuMacUIHostError.fileTooLarge }
        var result = urlDescription(url)
        result["content"] = .string(encoding == "base64" ? data.base64EncodedString() : String(decoding: data, as: UTF8.self))
        result["encoding"] = .string(encoding == "base64" ? "base64" : "utf8")
        return result
    }

    private func writeFile(_ url: URL, content: String, encoding: String?) throws {
        let data: Data
        if encoding == "base64" {
            guard let decoded = Data(base64Encoded: content) else { throw YanxuMacUIHostError.invalidFileContent }
            data = decoded
        } else {
            data = Data(content.utf8)
        }
        guard data.count <= 16 * 1024 * 1024 else { throw YanxuMacUIHostError.fileTooLarge }
        try data.write(to: url, options: [.atomic])
    }

    private func urlDescription(_ url: URL) -> [String: JSONValue] {
        var result: [String: JSONValue] = [
            "path": .string(url.path),
            "name": .string(url.lastPathComponent)
        ]
        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            result["bookmark"] = .string(bookmark.base64EncodedString())
        }
        return result
    }

    private func contentTypes(_ identifiers: [String]?) -> [UTType] {
        let values = identifiers ?? [UTType.data.identifier]
        return values.compactMap { UTType($0) ?? UTType(filenameExtension: $0) }
    }

    private func complete(_ request: YanxuMacUIRequest, cancelled: Bool = false, result: [String: JSONValue] = [:]) {
        onEvent("request.completed", [
            "request": .string(request.id),
            "kind": .string(request.type),
            "cancelled": .bool(cancelled),
            "result": .object(result)
        ])
    }

    private func fail(_ request: YanxuMacUIRequest, error: Error) {
        fail(request, message: String(describing: error))
    }

    private func fail(_ request: YanxuMacUIRequest, message: String) {
        onEvent("request.failed", [
            "request": .string(request.id),
            "kind": .string(request.type),
            "error": .string(message)
        ])
    }
}
