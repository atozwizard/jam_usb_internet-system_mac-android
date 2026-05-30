import AppKit
import Combine
import Foundation

enum ReaderPanel: String, CaseIterable, Identifiable {
    case log
    case macSetup
    case galaxySetup
    case usage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .log: return "로그"
        case .macSetup: return "Mac 설정"
        case .galaxySetup: return "Galaxy 설정"
        case .usage: return "사용 방법"
        }
    }

    var docFileName: String? {
        switch self {
        case .log: return nil
        case .macSetup: return "MAC_SETUP.md"
        case .galaxySetup: return "GALAXY_SETUP.md"
        case .usage: return "USAGE.md"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var doctor: DoctorReport?
    @Published var status: SystemStatusReport?
    @Published var logLines: [String] = []
    @Published var isSystemRunning = false
    @Published var isBusy = false
    @Published var cliMissing = false
    @Published var lastError: String?
    @Published var showRecoverConfirm = false
    @Published var showCloseWarning = false
    @Published var selectedPanel: ReaderPanel = .log
    @Published private(set) var docTexts: [String: String] = [:]

    private var systemProcess: Process?
    private var statusTimer: Timer?
    private let runner = CLIRunner.shared
    private let maxLogLines = 500

    func onAppear() {
        if runner.findCLIExecutable() == nil {
            cliMissing = true
            appendLog("[fail] jam-usb-internet not found next to this app.")
            return
        }

        refreshDoctor()
        refreshStatus()
        loadDocs()
        startStatusPolling()
    }

    func onDisappear() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    func applicationShouldTerminate() -> Bool {
        if isSystemRunning || isBusy {
            showCloseWarning = true
            return false
        }
        return true
    }

    func refreshDoctor() {
        Task {
            do {
                doctor = try runner.fetchDoctor()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func refreshStatus() {
        Task {
            do {
                let report = try runner.fetchSystemStatus()
                status = report
                isSystemRunning = report.state == .running || systemProcess?.isRunning == true
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func startSystem() {
        guard !isBusy, systemProcess == nil else { return }

        isBusy = true
        appendLog("[info] Starting USB internet (system mode)...")
        lastError = nil

        Task {
            do {
                let process = try runner.runCommand(arguments: ["system", "--force-tun", "--verbose"]) { [weak self] line in
                    self?.appendLog(line)
                } completion: { [weak self] code in
                    guard let self else { return }
                    self.systemProcess = nil
                    self.isSystemRunning = false
                    self.isBusy = false
                    if code != 0 {
                        if let reason = self.lastFailureLine() {
                            self.lastError = reason
                        }
                    }
                    self.appendLog("[info] System mode exited (code \(code)).")
                    self.refreshStatus()
                    self.refreshDoctor()
                }

                systemProcess = process
                isSystemRunning = true
                isBusy = false
                refreshStatus()
            } catch {
                isBusy = false
                isSystemRunning = false
                lastError = error.localizedDescription
                appendLog("[fail] \(error.localizedDescription)")
                appendLog("[info] Fallback: double-click Galaxy USB Internet ON.command")
            }
        }
    }

    func stopSystem() {
        guard !isBusy else { return }
        isBusy = true
        appendLog("[info] Stopping USB internet (system-stop)...")

        Task {
            do {
                _ = try runner.runCommand(arguments: ["system-stop"]) { [weak self] line in
                    self?.appendLog(line)
                } completion: { [weak self] _ in
                    guard let self else { return }
                    self.systemProcess?.terminate()
                    self.systemProcess = nil
                    self.isSystemRunning = false
                    self.isBusy = false
                    self.appendLog("[ok] Stop command finished.")
                    self.refreshStatus()
                }
            } catch {
                isBusy = false
                lastError = error.localizedDescription
                appendLog("[fail] \(error.localizedDescription)")
            }
        }
    }

    func recoverNetwork() {
        showRecoverConfirm = false
        guard !isBusy else { return }
        isBusy = true
        appendLog("[info] Running network recovery (system-recover)...")

        Task {
            do {
                _ = try runner.runCommand(arguments: ["system-recover"]) { [weak self] line in
                    self?.appendLog(line)
                } completion: { [weak self] _ in
                    guard let self else { return }
                    self.systemProcess?.terminate()
                    self.systemProcess = nil
                    self.isSystemRunning = false
                    self.isBusy = false
                    self.appendLog("[ok] Recovery command finished.")
                    self.refreshStatus()
                    self.refreshDoctor()
                }
            } catch {
                isBusy = false
                lastError = error.localizedDescription
                appendLog("[fail] \(error.localizedDescription)")
            }
        }
    }

    func openDoc(_ name: String) {
        switch name {
        case "MAC_SETUP.md":
            selectedPanel = .macSetup
        case "GALAXY_SETUP.md":
            selectedPanel = .galaxySetup
        case "USAGE.md":
            selectedPanel = .usage
        default:
            appendLog("[warn] Unknown doc: \(name)")
        }
    }

    func loadDocs() {
        for panel in ReaderPanel.allCases {
            guard let fileName = panel.docFileName else { continue }
            if let text = runner.loadDoc(named: fileName) {
                docTexts[fileName] = text
            } else {
                docTexts[fileName] = "문서를 찾을 수 없습니다: docs/\(fileName)\n\n배포 폴더에서 Jam USB Internet.app 과 같은 위치에 docs/ 가 있는지 확인하세요."
            }
        }
    }

    func showPanel(_ panel: ReaderPanel) {
        selectedPanel = panel
    }

    var statusSummary: String {
        guard let status else { return "상태 확인 중..." }
        var parts: [String] = [status.state.label]

        if status.adb.authorized, let model = status.adb.model {
            let maker = status.adb.manufacturer ?? "Galaxy"
            parts.append("\(maker) \(model)")
        } else if status.adb.found {
            parts.append("ADB: 기기 미승인")
        } else {
            parts.append("ADB 없음")
        }

        if status.singBoxRunning {
            parts.append("sing-box 실행 중")
        }
        if status.relayRunning {
            parts.append("relay 실행 중")
        }
        if let iface = status.routeInterface {
            parts.append("route: \(iface)")
        }

        return parts.joined(separator: " · ")
    }

    private func startStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > maxLogLines {
            logLines.removeFirst(logLines.count - maxLogLines)
        }
    }

    private func lastFailureLine() -> String? {
        logLines.reversed().first { line in
            line.contains("[fail]") || line.contains("launchctl guard submit failed")
        }
    }

    var logText: String {
        logLines.joined(separator: "\n")
    }

    var panelText: String {
        switch selectedPanel {
        case .log:
            return logText
        case .macSetup, .galaxySetup, .usage:
            guard let fileName = selectedPanel.docFileName else { return "" }
            return docTexts[fileName] ?? "문서를 불러오는 중..."
        }
    }

    func copyPanelText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(panelText, forType: .string)
    }

    func copyAllLogs() {
        copyPanelText()
    }

    func clearLogs() {
        logLines.removeAll()
    }
}
