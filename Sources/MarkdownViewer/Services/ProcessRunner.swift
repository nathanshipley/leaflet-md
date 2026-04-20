import Foundation

enum ProcessRunner {
    static func run(launchPath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: errorData, as: UTF8.self)
            throw ProcessRunnerError.commandFailed(status: process.terminationStatus, stderr: stderr)
        }

        return String(decoding: outputData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ProcessRunnerError: LocalizedError {
    case commandFailed(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(status, stderr):
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.isEmpty {
                return "Command failed with status \(status)."
            }

            return "Command failed with status \(status): \(message)"
        }
    }
}
