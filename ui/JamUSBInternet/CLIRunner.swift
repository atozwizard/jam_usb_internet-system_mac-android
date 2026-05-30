import AppKit
import Foundation

final class CLIRunner {
    static let shared = CLIRunner()

    private init() {}

    func findCLIExecutable() -> URL? {
        if let override = ProcessInfo.processInfo.environment["JAM_USB_CLI_PATH"] {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let bundleURL = Bundle.main.bundleURL
        let sibling = bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("jam-usb-internet")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }

        var dir = bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("jam-usb-internet")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }

        return nil
    }

    func packageRoot() -> URL? {
        guard let cli = findCLIExecutable() else { return nil }
        return cli.deletingLastPathComponent()
    }

    func docsURL(named name: String) -> URL? {
        guard let root = packageRoot() else { return nil }
        let docs = root.appendingPathComponent("docs/\(name)")
        if FileManager.default.fileExists(atPath: docs.path) {
            return docs
        }
        return nil
    }

    func loadDoc(named name: String) -> String? {
        guard let url = docsURL(named: name) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func findAskPassExecutable() -> URL? {
        if let override = ProcessInfo.processInfo.environment["JAM_USB_SUDO_ASKPASS"] {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        guard let root = packageRoot() else { return nil }
        let sibling = root.appendingPathComponent("jam-usb-askpass")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }
        return nil
    }

    func configureProcessEnvironment(_ process: Process) {
        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        env["HOME"] = home
        env["USER"] = env["USER"] ?? NSUserName()
        env["TMPDIR"] = env["TMPDIR"] ?? NSTemporaryDirectory()
        env["JAM_USB_STATE_DIR"] = env["JAM_USB_STATE_DIR"] ?? "\(home)/.jam-usb-internet"
        if let askpass = findAskPassExecutable() {
            env["JAM_USB_SUDO_ASKPASS"] = askpass.path
            env["SUDO_ASKPASS"] = askpass.path
        }
        let pathPrefix = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = "\(pathPrefix):\(env["PATH"] ?? "")"
        process.environment = env
    }

    func primeAdministratorPrivileges() throws {
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/sudo") {
            let check = Process()
            check.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            check.arguments = ["-n", "true"]
            configureProcessEnvironment(check)
            check.standardOutput = Pipe()
            check.standardError = Pipe()
            try check.run()
            check.waitUntilExit()
            if check.terminationStatus == 0 {
                return
            }
        }

        guard findAskPassExecutable() != nil else {
            throw CLIError.sudoFailed("jam-usb-askpass helper not found next to jam-usb-internet.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-A", "-v"]
        configureProcessEnvironment(process)
        let err = Pipe()
        process.standardOutput = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw CLIError.sudoFailed(msg.isEmpty ? "Could not obtain administrator privileges." : msg)
        }
    }

    func fetchDoctor() throws -> DoctorReport {
        try runJSON(arguments: ["doctor", "--json"])
    }

    func fetchSystemStatus() throws -> SystemStatusReport {
        try runJSON(arguments: ["system-status", "--json"])
    }

    @discardableResult
    func runCommand(
        arguments: [String],
        onLine: ((String) -> Void)? = nil,
        completion: ((Int32) -> Void)? = nil
    ) throws -> Process {
        guard let cli = findCLIExecutable() else {
            throw CLIError.cliNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [cli.path] + arguments
        process.currentDirectoryURL = cli.deletingLastPathComponent()
        configureProcessEnvironment(process)

        if let onLine {
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                for line in chunk.components(separatedBy: .newlines) where !line.isEmpty {
                    DispatchQueue.main.async {
                        onLine(line)
                    }
                }
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                if let completion {
                    DispatchQueue.main.async {
                        completion(proc.terminationStatus)
                    }
                }
            }
        } else if let completion {
            process.terminationHandler = { proc in
                DispatchQueue.main.async {
                    completion(proc.terminationStatus)
                }
            }
        }

        try process.run()
        return process
    }

    private func runJSON<T: Decodable>(arguments: [String]) throws -> T {
        guard let cli = findCLIExecutable() else {
            throw CLIError.cliNotFound
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [cli.path] + arguments
        process.currentDirectoryURL = cli.deletingLastPathComponent()
        configureProcessEnvironment(process)
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw CLIError.commandFailed(text.isEmpty ? "exit \(process.terminationStatus)" : text)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw CLIError.decodeFailed("\(error.localizedDescription)\n\(text)")
        }
    }
}
