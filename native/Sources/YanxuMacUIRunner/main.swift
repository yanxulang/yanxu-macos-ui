import Foundation
import YanxuMacUIHost

@main
struct YanxuMacUIRunner {
    static func readInput() throws -> Data {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.count >= 2, arguments[0] == "--json" {
            return Data(arguments[1].utf8)
        }
        if let path = arguments.first, path != "-" {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        }
        return FileHandle.standardInput.readDataToEndOfFile()
    }

    @MainActor
    static func main() {
        do {
            let data = try readInput()
            guard !data.isEmpty else {
                fputs("yanxu-macos-ui-runner: 需要应用 JSON，可传文件路径或从标准输入读取。\n", stderr)
                exit(64)
            }
            let host = YanxuMacUIAppHost()
            try host.launch(from: data) { name, payload in
                NSLog("YanxuMacUI event %@ %@", name, payload)
            }
        } catch {
            fputs("yanxu-macos-ui-runner: \(error)\n", stderr)
            exit(1)
        }
    }
}
