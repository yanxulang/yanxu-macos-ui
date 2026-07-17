import AppKit
import SwiftUI

extension YanxuMacUIRenderer {
    func renderControl(_ view: YanxuMacUIView) -> AnyView? {
        switch view.kind {
        case "Text":
            let value = view.binding.map { _ in store.value(for: view, fallback: .string("")) }
            return AnyView(Text(value?.stringValue ?? view.text ?? ""))
        case "Button": return AnyView(Button(view.title ?? "Button") { emit(view.event, source: view.stableID) })
        case "TextField", "SearchField":
            return AnyView(TextField(view.placeholder ?? "", text: textBinding(for: view)).textFieldStyle(.roundedBorder))
        case "SecureField":
            return AnyView(SecureField(view.placeholder ?? "", text: textBinding(for: view)).textFieldStyle(.roundedBorder))
        case "TextEditor":
            return AnyView(TextEditor(text: textBinding(for: view)).font(.body).frame(minHeight: 120))
        case "Toggle": return AnyView(Toggle(view.title ?? "", isOn: boolBinding(for: view)))
        case "Picker":
            let picker = Picker(view.title ?? "", selection: textBinding(for: view)) {
                ForEach(options(for: view), id: \.value) { option in Text(option.title).tag(option.value) }
            }
            if view.properties["pickerStyle"]?.optionalString == "segmented" {
                return AnyView(picker.pickerStyle(.segmented))
            }
            return AnyView(picker)
        case "Slider":
            return AnyView(Slider(value: numberBinding(for: view), in: range(for: view), step: view.step ?? 0.01))
        case "Stepper":
            return AnyView(Stepper(value: numberBinding(for: view), in: range(for: view), step: view.step ?? 1) {
                HStack {
                    Text(view.title ?? "")
                    Spacer(minLength: 8)
                    Text(formattedNumber(numberBinding(for: view).wrappedValue))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            })
        case "DatePicker": return AnyView(DatePicker(view.title ?? "", selection: dateBinding(for: view)))
        case "ColorPicker": return AnyView(ColorPicker(view.title ?? "", selection: colorBinding(for: view)))
        case "Label": return AnyView(Label(view.title ?? "", systemImage: view.systemName ?? "app"))
        case "Link":
            guard let rawURL = view.url, let url = URL(string: rawURL) else {
                return AnyView(Text(view.title ?? "Invalid link").foregroundStyle(.secondary))
            }
            return AnyView(Link(view.title ?? rawURL, destination: url))
        case "Menu":
            return AnyView(Menu(view.title ?? "Menu") {
                ForEach(Array(menuItems(for: view).enumerated()), id: \.offset) { _, item in
                    Button(item.title) { emit(item.event, source: view.stableID) }
                }
            })
        case "Image": return AnyView(Image(systemName: view.systemName ?? "app").imageScale(.large))
        case "Spacer": return AnyView(Spacer(minLength: view.size.map { CGFloat($0) }))
        case "Divider": return AnyView(Divider())
        case "ProgressView":
            return AnyView(ProgressView(value: store.value(for: view, fallback: view.value ?? .number(0)).numberValue))
        default: return nil
        }
    }

    private func formattedNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    func textBinding(for view: YanxuMacUIView) -> Binding<String> {
        Binding(
            get: { store.value(for: view, fallback: .string("")).stringValue },
            set: { value in
                store.setValue(.string(value), for: view)
                emitChange(for: view, value: .string(value))
            }
        )
    }

    func boolBinding(for view: YanxuMacUIView) -> Binding<Bool> {
        Binding(
            get: { store.value(for: view, fallback: .bool(false)).boolValue },
            set: { value in
                store.setValue(.bool(value), for: view)
                emitChange(for: view, value: .bool(value))
            }
        )
    }

    func numberBinding(for view: YanxuMacUIView) -> Binding<Double> {
        Binding(
            get: { store.value(for: view, fallback: .number(0)).numberValue },
            set: { value in
                store.setValue(.number(value), for: view)
                emitChange(for: view, value: .number(value))
            }
        )
    }

    func dateBinding(for view: YanxuMacUIView) -> Binding<Date> {
        Binding(
            get: {
                let raw = store.value(for: view, fallback: .string("")).stringValue
                return ISO8601DateFormatter().date(from: raw) ?? Date()
            },
            set: { date in
                let value = JSONValue.string(ISO8601DateFormatter().string(from: date))
                store.setValue(value, for: view)
                emitChange(for: view, value: value)
            }
        )
    }

    func colorBinding(for view: YanxuMacUIView) -> Binding<Color> {
        Binding(
            get: { Color(yanxuHex: store.value(for: view, fallback: .string("#007AFF")).stringValue) },
            set: { color in
                let value = JSONValue.string(color.hexString)
                store.setValue(value, for: view)
                emitChange(for: view, value: value)
            }
        )
    }

    func options(for view: YanxuMacUIView) -> [YanxuMacUIOption] {
        (view.items ?? []).compactMap { item in
            guard let object = item.optionalObject,
                  let title = object["title"]?.optionalString,
                  let value = object["value"]?.optionalString else { return nil }
            return YanxuMacUIOption(title: title, value: value)
        }
    }

    private func menuItems(for view: YanxuMacUIView) -> [YanxuMacUIMenuButtonItem] {
        (view.items ?? []).compactMap { item in
            guard let object = item.optionalObject,
                  let title = object["title"]?.optionalString,
                  let event = object["event"]?.optionalString else { return nil }
            return YanxuMacUIMenuButtonItem(title: title, event: event)
        }
    }

    private func range(for view: YanxuMacUIView) -> ClosedRange<Double> {
        (view.minimum ?? 0)...(view.maximum ?? 1)
    }
}

struct YanxuMacUIOption {
    let title: String
    let value: String
}

private struct YanxuMacUIMenuButtonItem {
    let title: String
    let event: String
}

extension Color {
    init(yanxuHex hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        let divisor = 255.0
        if value.count == 8 {
            self.init(
                red: Double((rgb >> 24) & 0xff) / divisor,
                green: Double((rgb >> 16) & 0xff) / divisor,
                blue: Double((rgb >> 8) & 0xff) / divisor,
                opacity: Double(rgb & 0xff) / divisor
            )
        } else {
            self.init(
                red: Double((rgb >> 16) & 0xff) / divisor,
                green: Double((rgb >> 8) & 0xff) / divisor,
                blue: Double(rgb & 0xff) / divisor
            )
        }
    }

    var hexString: String {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else { return "#007AFF" }
        return String(
            format: "#%02X%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255)),
            Int(round(color.alphaComponent * 255))
        )
    }
}
