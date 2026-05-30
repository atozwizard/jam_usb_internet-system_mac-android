import Foundation

struct DoctorReport: Codable {
    let version: String
    let ready: Bool
    let mac: MacInfo
    let adb: ADBInfo
    let singBox: SingBoxInfo
    let checks: [PreflightCheck]

    enum CodingKeys: String, CodingKey {
        case version, ready, mac, adb, checks
        case singBox = "sing_box"
    }
}

struct MacInfo: Codable {
    let osVersion: String
    let arch: String

    enum CodingKeys: String, CodingKey {
        case osVersion = "os_version"
        case arch
    }
}

struct ADBInfo: Codable {
    let found: Bool
    let path: String?
    let authorized: Bool
    let serial: String?
    let manufacturer: String?
    let model: String?
}

struct SingBoxInfo: Codable {
    let found: Bool
    let path: String?

    enum CodingKeys: String, CodingKey {
        case found, path
    }
}

struct PreflightCheck: Codable, Identifiable {
    var id: String { name }
    let name: String
    let ok: Bool
    let message: String
}

struct SystemStatusReport: Codable {
    let version: String
    let state: SystemState
    let singBoxRunning: Bool
    let relayRunning: Bool
    let dnsTempActive: Bool
    let guardActive: Bool
    let guardPid: String?
    let guardLabel: String?
    let routeInterface: String?
    let adb: ADBInfo

    enum CodingKeys: String, CodingKey {
        case version, state, adb
        case singBoxRunning = "sing_box_running"
        case relayRunning = "relay_running"
        case dnsTempActive = "dns_temp_active"
        case guardActive = "guard_active"
        case guardPid = "guard_pid"
        case guardLabel = "guard_label"
        case routeInterface = "route_interface"
    }
}

enum SystemState: String, Codable {
    case idle
    case running
    case partial
    case needsRecover = "needs_recover"

    var label: String {
        switch self {
        case .idle: return "대기"
        case .running: return "연결됨"
        case .partial: return "부분 실행"
        case .needsRecover: return "복구 필요"
        }
    }
}

enum CLIError: LocalizedError {
    case cliNotFound
    case decodeFailed(String)
    case commandFailed(String)
    case sudoFailed(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "jam-usb-internet 실행 파일을 찾을 수 없습니다. 앱과 같은 폴더에 배치되어 있는지 확인하세요."
        case .decodeFailed(let detail):
            return "상태 응답을 해석하지 못했습니다: \(detail)"
        case .commandFailed(let detail):
            return "명령 실행 실패: \(detail)"
        case .sudoFailed(let detail):
            return "관리자 권한이 필요합니다: \(detail)"
        }
    }
}
