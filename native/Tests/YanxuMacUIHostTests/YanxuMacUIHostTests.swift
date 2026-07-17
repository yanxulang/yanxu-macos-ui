import AppKit
import SwiftUI
import XCTest
@testable import YanxuMacUIHost

private var retainedHandles: [UInt64] = []
private var releasedHandles: [UInt64] = []
private var postedEventName = ""
private var postedPayloadSource = ""
private var pumpCount = 0

private let fakeRetain: YanxuNativeCallbackRetainV2 = { _, handle in
    retainedHandles.append(handle)
    return yanxuNativeOK
}

private let fakeRelease: YanxuNativeCallbackReleaseV2 = { _, handle in
    releasedHandles.append(handle)
    return yanxuNativeOK
}

private let fakePost: YanxuNativeCallbackPostV2 = { _, _, rawArguments, count, _ in
    guard count == 2, let rawArguments else { return 1 }
    let arguments = rawArguments.assumingMemoryBound(to: YanxuNativeValueV2.self)
    postedEventName = decodeString(arguments[0])
    let payload = arguments[1]
    guard payload.kind == yanxuNativeValueMapV2,
          let rawItems = UnsafeRawPointer(bitPattern: UInt(payload.data)) else { return 1 }
    let items = rawItems.assumingMemoryBound(to: YanxuNativeValueV2.self)
    for index in 0..<Int(payload.length) where decodeString(items[index * 2]) == "source" {
        postedPayloadSource = decodeString(items[index * 2 + 1])
    }
    return yanxuNativeOK
}

private let fakePump: YanxuNativeHostPumpV2 = { _, _, _ in
    pumpCount += 1
    return yanxuNativeOK
}

private func decodeString(_ value: YanxuNativeValueV2) -> String {
    guard value.kind == yanxuNativeValueStringV2,
          value.length > 0,
          let raw = UnsafeRawPointer(bitPattern: UInt(value.data)) else { return "" }
    let bytes = raw.assumingMemoryBound(to: UInt8.self)
    return String(bytes: UnsafeBufferPointer(start: bytes, count: Int(value.length)), encoding: .utf8) ?? ""
}

final class YanxuMacUIHostTests: XCTestCase {
    override func setUp() {
        retainedHandles = []
        releasedHandles = []
        postedEventName = ""
        postedPayloadSource = ""
        pumpCount = 0
    }

    func testCallbackPostsTypedEventAndPumpsOwnerThread() {
        var host = YanxuNativeHostV2(
            abiVersion: yanxuNativeABIVersionV2,
            structSize: MemoryLayout<YanxuNativeHostV2>.size,
            context: nil,
            callbackRetain: unsafeBitCast(fakeRetain, to: UnsafeRawPointer.self),
            callbackRelease: unsafeBitCast(fakeRelease, to: UnsafeRawPointer.self),
            callbackPost: unsafeBitCast(fakePost, to: UnsafeRawPointer.self),
            wake: nil,
            pump: unsafeBitCast(fakePump, to: UnsafeRawPointer.self),
            hasPermission: nil,
            resourceGet: nil,
            eventLoopID: 7,
            ownerThreadToken: 7
        )
        let argument = YanxuNativeValueV2(
            kind: yanxuNativeValueCallbackV2,
            flags: 0,
            length: 0,
            data: 42
        )
        let callback = withUnsafePointer(to: &host) { YanxuMacUICallback(argument: argument, host: $0) }

        XCTAssertTrue(callback?.retain() == true)
        XCTAssertTrue(callback?.post(name: "counter.increment", payload: ["source": .string("increment")]) == true)
        callback?.release()

        XCTAssertEqual(retainedHandles, [42])
        XCTAssertEqual(releasedHandles, [42])
        XCTAssertEqual(postedEventName, "counter.increment")
        XCTAssertEqual(postedPayloadSource, "increment")
        XCTAssertEqual(pumpCount, 1)
    }

    func testViewUsesGenericPropertyBagAndStoreAcceptsSnapshotUpdate() throws {
        let first = Data(#"{"schema":"dev.yanxu.mac-ui.v1","name":"Test","windows":[{"title":"Main","root":{"kind":"TextField","id":"title","customFlag":true,"value":"one","children":[]}}]}"#.utf8)
        let second = Data(#"{"schema":"dev.yanxu.mac-ui.v1","name":"Test","windows":[{"title":"Updated","root":{"kind":"TextField","id":"title","customFlag":false,"value":"one","children":[]}}]}"#.utf8)
        let third = Data(#"{"schema":"dev.yanxu.mac-ui.v1","name":"Test","windows":[{"title":"Updated","root":{"kind":"TextField","id":"title","customFlag":false,"value":"server","children":[]}}]}"#.utf8)
        let initial = try JSONDecoder().decode(YanxuMacUIApplication.self, from: first)
        let updated = try JSONDecoder().decode(YanxuMacUIApplication.self, from: second)
        let overridden = try JSONDecoder().decode(YanxuMacUIApplication.self, from: third)
        let store = YanxuMacUIApplicationStore(application: initial)

        XCTAssertEqual(initial.windows[0].root.properties["customFlag"], .bool(true))
        store.setValue(.string("typed"), for: initial.windows[0].root)
        store.update(application: updated)
        XCTAssertEqual(store.application.windows[0].title, "Updated")
        XCTAssertEqual(store.value(for: updated.windows[0].root, fallback: .null), .string("typed"))
        store.update(application: overridden)
        XCTAssertEqual(store.value(for: overridden.windows[0].root, fallback: .null), .string("server"))
    }

    func testSchemaV2BindingEmitsStateIdentityAndRevision() throws {
        let data = Data(#"{"schema":"dev.yanxu.mac-ui.v2","revision":4,"state":[{"id":"document.title","type":"string","value":"Draft"}],"name":"Test","windows":[{"title":"Main","root":{"kind":"TextField","id":"title-field","binding":"document.title","bindingType":"string","children":[]}}]}"#.utf8)
        let application = try JSONDecoder().decode(YanxuMacUIApplication.self, from: data)
        try application.validate()
        let store = YanxuMacUIApplicationStore(application: application)
        var eventName = ""
        var payload: YanxuMacUIEventPayload = [:]
        let renderer = YanxuMacUIRenderer(store: store, windowIndex: 0) { name, value in
            eventName = name
            payload = value
        }

        XCTAssertEqual(store.value(for: application.windows[0].root, fallback: .null), .string("Draft"))
        renderer.textBinding(for: application.windows[0].root).wrappedValue = "Published"

        XCTAssertEqual(eventName, "binding.changed")
        XCTAssertEqual(payload["binding"], .string("document.title"))
        XCTAssertEqual(payload["revision"], .number(4))
        XCTAssertEqual(payload["value"], .string("Published"))
    }

    func testStatePatchIsRevisionOrdered() throws {
        let data = Data(#"{"schema":"dev.yanxu.mac-ui.v2","revision":4,"state":[{"id":"document.title","type":"string","value":"Draft"}],"name":"Test","windows":[{"title":"Main","root":{"kind":"TextField","id":"title-field","binding":"document.title","bindingType":"string","children":[]}}]}"#.utf8)
        let application = try JSONDecoder().decode(YanxuMacUIApplication.self, from: data)
        let view = application.windows[0].root
        let store = YanxuMacUIApplicationStore(application: application)
        let stale = try JSONDecoder().decode(YanxuMacUIStatePatch.self, from: Data(#"{"schema":"dev.yanxu.mac-ui.state.v1","revision":3,"state":[{"id":"document.title","type":"string","value":"Stale"}]}"#.utf8))
        let fresh = try JSONDecoder().decode(YanxuMacUIStatePatch.self, from: Data(#"{"schema":"dev.yanxu.mac-ui.state.v1","revision":5,"state":[{"id":"document.title","type":"string","value":"Fresh"}]}"#.utf8))

        store.patch(stale)
        XCTAssertEqual(store.value(for: view, fallback: .null), .string("Draft"))
        store.patch(fresh)
        XCTAssertEqual(store.value(for: view, fallback: .null), .string("Fresh"))
        XCTAssertEqual(store.application.revision, 5)
    }

    func testSchemaV2RejectsDuplicateIDsAndTypeMismatch() throws {
        let duplicate = Data(#"{"schema":"dev.yanxu.mac-ui.v2","revision":0,"state":[{"id":"title","type":"string","value":"A"},{"id":"title","type":"string","value":"B"}],"name":"Test","windows":[{"title":"Main","root":{"kind":"Text","text":"Hello","children":[]}}]}"#.utf8)
        let mismatch = Data(#"{"schema":"dev.yanxu.mac-ui.v2","revision":0,"state":[{"id":"enabled","type":"bool","value":"yes"}],"name":"Test","windows":[{"title":"Main","root":{"kind":"Text","text":"Hello","children":[]}}]}"#.utf8)
        let wrongControlType = Data(#"{"schema":"dev.yanxu.mac-ui.v2","revision":0,"state":[{"id":"enabled","type":"bool","value":true}],"name":"Test","windows":[{"title":"Main","root":{"kind":"Slider","id":"volume","binding":"enabled","bindingType":"bool","children":[]}}]}"#.utf8)
        let invalidRange = Data(#"{"schema":"dev.yanxu.mac-ui.v2","revision":0,"state":[{"id":"volume","type":"number","value":1}],"name":"Test","windows":[{"title":"Main","root":{"kind":"Slider","id":"volume-slider","binding":"volume","bindingType":"number","minimum":10,"maximum":0,"step":1,"children":[]}}]}"#.utf8)
        let invalidTable = Data(#"{"schema":"dev.yanxu.mac-ui.v2","revision":0,"state":[{"id":"selection","type":"selection","value":[]}],"name":"Test","windows":[{"title":"Main","root":{"kind":"Table","id":"table","binding":"selection","bindingType":"selection","columns":[{"title":"Name","key":"name"},{"title":"Duplicate","key":"name"}],"items":[{"id":"row","name":"One"}],"children":[]}}]}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(YanxuMacUIApplication.self, from: duplicate).validate())
        XCTAssertThrowsError(try JSONDecoder().decode(YanxuMacUIApplication.self, from: mismatch).validate())
        XCTAssertThrowsError(try JSONDecoder().decode(YanxuMacUIApplication.self, from: wrongControlType).validate())
        XCTAssertThrowsError(try JSONDecoder().decode(YanxuMacUIApplication.self, from: invalidRange).validate())
        XCTAssertThrowsError(try JSONDecoder().decode(YanxuMacUIApplication.self, from: invalidTable).validate())
    }

    func testMenuBarOnlyApplicationSupportsArbitraryBoundContent() throws {
        let data = Data(#"{"schema":"dev.yanxu.mac-ui.v2","revision":0,"state":[{"id":"menu.enabled","type":"bool","value":true}],"name":"Status Test","windows":[],"menuBarItems":[{"id":"status-main","systemName":"star.fill","tooltip":"Status Test","size":{"width":320,"height":240},"content":{"kind":"VStack","children":[{"kind":"Text","text":"Status","children":[]},{"kind":"Toggle","id":"status-toggle","title":"Enabled","binding":"menu.enabled","bindingType":"bool","children":[]}]}}]}"#.utf8)
        let application = try JSONDecoder().decode(YanxuMacUIApplication.self, from: data)

        XCTAssertNoThrow(try application.validate())
        XCTAssertTrue(application.windows.isEmpty)
        XCTAssertEqual(application.menuBarItems?.first?.systemName, "star.fill")
        XCTAssertEqual(application.menuBarItems?.first?.content.children?.last?.binding, "menu.enabled")
    }

    @MainActor
    func testFormControlsStayWithinPopoverWidth() throws {
        _ = NSApplication.shared
        let data = Data(#"{"schema":"dev.yanxu.mac-ui.v2","revision":0,"state":[{"id":"url","type":"string","value":"http://127.0.0.1:8080"},{"id":"minimum","type":"number","value":1}],"name":"Form Test","windows":[{"title":"Main","root":{"kind":"Form","children":[{"kind":"TextField","id":"url-field","placeholder":"服务地址","binding":"url","bindingType":"string","children":[]},{"kind":"Stepper","id":"minimum-stepper","title":"最少可用账号","binding":"minimum","bindingType":"number","minimum":1,"maximum":100,"step":1,"children":[]}]}}]}"#.utf8)
        let application = try JSONDecoder().decode(YanxuMacUIApplication.self, from: data)
        let store = YanxuMacUIApplicationStore(application: application)
        let renderer = YanxuMacUIRenderer(store: store, windowIndex: 0) { _, _ in }
        let host = NSHostingView(rootView: renderer.frame(width: 320, alignment: .leading))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        host.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(host.fittingSize.width, 320.5)
        XCTAssertEqual(store.value(for: application.windows[0].root.children![1], fallback: .null), .number(1))
    }

    @MainActor
    func testMenuBarControllerInstallsNativeStatusItem() throws {
        _ = NSApplication.shared
        let data = Data(#"{"schema":"dev.yanxu.mac-ui.v2","revision":0,"state":[],"name":"Status Test","windows":[],"menuBarItems":[{"id":"status-main","systemName":"star.fill","tooltip":"Status Test","size":{"width":320,"height":240},"content":{"kind":"Text","text":"Status","children":[]}}]}"#.utf8)
        let application = try JSONDecoder().decode(YanxuMacUIApplication.self, from: data)
        let store = YanxuMacUIApplicationStore(application: application)
        let description = try XCTUnwrap(application.menuBarItems?.first)
        let controller = YanxuMacUIMenuBarItemController(description: description, store: store) { _, _ in }
        defer { controller.invalidate() }

        XCTAssertTrue(controller.hasStatusButton)
        XCTAssertEqual(controller.contentSize.width, 320)
        XCTAssertEqual(controller.contentSize.height, 240)
        controller.togglePopover()
        XCTAssertTrue(controller.isPopoverShown)
    }

    @MainActor
    func testStopTerminatesApplicationExactlyOnce() {
        var terminationCount = 0
        let host = YanxuMacUIAppHost { terminationCount += 1 }

        host.stop()
        host.stop()

        XCTAssertEqual(terminationCount, 1)
    }

    func testVersionSixApplicationModelValidatesScenesNavigationAndCommands() throws {
        let data = Data(#"""
        {
          "schema":"dev.yanxu.mac-ui.v2","revision":0,"name":"Complete",
          "state":[
            {"id":"focus.current","type":"string","value":"title-field"},
            {"id":"document.content","type":"string","value":""},
            {"id":"document.path","type":"string","value":""},
            {"id":"navigation.path","type":"selection","value":[]},
            {"id":"table.selection","type":"selection","value":[]},
            {"id":"inspector.visible","type":"bool","value":true},
            {"id":"command.enabled","type":"bool","value":true}
          ],
          "windows":[{
            "id":"main","title":"Main","restorationID":"main","initiallyVisible":true,
            "toolbar":[{"id":"open","title":"Open","event":"file.open","systemName":"folder","placement":"primary","enabledBinding":"command.enabled"}],
            "root":{"kind":"VStack","children":[
              {"kind":"TextField","id":"title-field","value":"","focusBinding":"focus.current","children":[]},
              {"kind":"NavigationStack","id":"navigation","binding":"navigation.path","bindingType":"selection","children":[
                {"kind":"NavigationDestination","id":"overview","title":"Overview","children":[{"kind":"Text","text":"Overview","children":[]}]}
              ]},
              {"kind":"Table","id":"table","binding":"table.selection","bindingType":"selection","columns":[{"title":"Name","key":"name"}],"items":[{"id":"one","name":"One"}],"children":[]},
              {"kind":"Inspector","id":"inspector","binding":"inspector.visible","bindingType":"bool","children":[{"kind":"Text","text":"Content","children":[]},{"kind":"Text","text":"Details","children":[]}]}
            ]}
          }],
          "menus":[{"title":"File","placement":"file","items":[{"id":"open-command","title":"Open","event":"file.open","role":"normal","enabledBinding":"command.enabled"}]}],
          "settings":{"kind":"Text","text":"Settings","children":[]},
          "settingsSize":{"width":640,"height":420},
          "documents":[{"id":"text-document","title":"Text","contentTypes":["public.plain-text"],"defaultFilename":"Untitled.txt","contentBinding":"document.content","pathBinding":"document.path","root":{"kind":"Text","text":"Document","children":[]}}]
        }
        """#.utf8)

        let application = try JSONDecoder().decode(YanxuMacUIApplication.self, from: data)

        XCTAssertNoThrow(try application.validate())
        XCTAssertEqual(application.windows.first?.id, "main")
        XCTAssertEqual(application.documents?.first?.contentTypes, ["public.plain-text"])
        XCTAssertEqual(application.windows.first?.toolbar?.first?.placement, "primary")
    }

    @MainActor
    func testRequestCoordinatorCorrelatesWindowSettingsAndDocumentResults() throws {
        var events: [(String, YanxuMacUIEventPayload)] = []
        var openedWindow = ""
        var openedDocument = ""
        let coordinator = YanxuMacUIRequestCoordinator(
            onEvent: { events.append(($0, $1)) },
            openWindow: { openedWindow = $0; return true },
            closeWindow: { _ in true },
            openSettings: { true },
            openDocument: { scene, _, _ in openedDocument = scene; return "document-1" }
        )
        let decoder = JSONDecoder()

        try coordinator.perform(decoder.decode(YanxuMacUIRequest.self, from: Data(#"{"id":"open-window","type":"window.open","windowID":"activity"}"#.utf8)))
        try coordinator.perform(decoder.decode(YanxuMacUIRequest.self, from: Data(#"{"id":"open-settings","type":"settings.open"}"#.utf8)))
        try coordinator.perform(decoder.decode(YanxuMacUIRequest.self, from: Data(#"{"id":"new-document","type":"document.new","sceneID":"text-document","suggestedName":"Draft.txt"}"#.utf8)))

        XCTAssertEqual(openedWindow, "activity")
        XCTAssertEqual(openedDocument, "text-document")
        XCTAssertEqual(events.map(\.0), ["request.completed", "request.completed", "request.completed"])
        XCTAssertEqual(events.last?.1["request"], .string("new-document"))
        XCTAssertEqual(events.last?.1["result"], .object(["document": .string("document-1")]))
    }
}
