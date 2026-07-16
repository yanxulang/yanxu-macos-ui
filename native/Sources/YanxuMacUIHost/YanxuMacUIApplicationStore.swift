import SwiftUI

final class YanxuMacUIApplicationStore: ObservableObject {
    @Published private(set) var application: YanxuMacUIApplication
    private var controlValues: [String: JSONValue] = [:]
    private var modelControlValues: [String: JSONValue] = [:]
    private var stateValues: [String: JSONValue] = [:]

    init(application: YanxuMacUIApplication) {
        self.application = application
        modelControlValues = collectControlValues(from: application)
        controlValues = modelControlValues
        stateValues = Dictionary(uniqueKeysWithValues: (application.state ?? []).map { ($0.id, $0.value) })
    }

    func update(application: YanxuMacUIApplication) {
        if application.schema == "dev.yanxu.mac-ui.v2" {
            stateValues = Dictionary(uniqueKeysWithValues: (application.state ?? []).map { ($0.id, $0.value) })
            self.application = application
            return
        }
        let nextModelValues = collectControlValues(from: application)
        var nextControlValues: [String: JSONValue] = [:]
        for (identifier, modelValue) in nextModelValues {
            if modelControlValues[identifier] == modelValue, let localValue = controlValues[identifier] {
                nextControlValues[identifier] = localValue
            } else {
                nextControlValues[identifier] = modelValue
            }
        }
        modelControlValues = nextModelValues
        controlValues = nextControlValues
        self.application = application
    }

    func value(for view: YanxuMacUIView, fallback: JSONValue) -> JSONValue {
        if let binding = view.binding { return stateValues[binding] ?? fallback }
        return controlValues[view.stableID] ?? view.value ?? fallback
    }

    func setValue(_ value: JSONValue, for view: YanxuMacUIView) {
        objectWillChange.send()
        if let binding = view.binding {
            stateValues[binding] = value
        } else {
            controlValues[view.stableID] = value
        }
    }

    func patch(_ patch: YanxuMacUIStatePatch) {
        guard patch.revision > (application.revision ?? -1) else { return }
        objectWillChange.send()
        stateValues = Dictionary(uniqueKeysWithValues: patch.state.map { ($0.id, $0.value) })
        application.revision = patch.revision
        application.state = patch.state
    }

    private func collectControlValues(from application: YanxuMacUIApplication) -> [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        for window in application.windows {
            collectControlValues(from: window.root, into: &values)
        }
        return values
    }

    private func collectControlValues(from view: YanxuMacUIView, into values: inout [String: JSONValue]) {
        switch view.kind {
        case "TextField", "TextEditor": values[view.stableID] = view.value ?? .string("")
        case "SecureField": values[view.stableID] = .string("")
        case "Toggle": values[view.stableID] = view.value ?? .bool(false)
        default: break
        }
        for child in view.children ?? [] {
            collectControlValues(from: child, into: &values)
        }
    }
}
