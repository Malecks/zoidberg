import Foundation

struct CommandResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol CommandRunner {
    func run(_ executable: String, _ args: [String]) async -> CommandResult
}

struct ProcessCommandRunner: CommandRunner {
    static func environment(base: [String: String], home: String) -> [String: String] {
        var env = base
        env["PATH"] = "/opt/homebrew/bin:\(home)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOME"] = home
        return env
    }

    func run(_ executable: String, _ args: [String]) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.environment = Self.environment(base: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: CommandResult(exitCode: process.terminationStatus,
                                                             stdout: String(decoding: outData, as: UTF8.self),
                                                             stderr: String(decoding: errData, as: UTF8.self)))
            }
        }
    }
}
