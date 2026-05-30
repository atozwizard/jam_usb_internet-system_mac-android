import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusHeader
            actionButtons
            warningBanner
            preflightSection
            readerSection
            footerBar
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 620)
        .alert("네트워크 복구", isPresented: $viewModel.showRecoverConfirm) {
            Button("취소", role: .cancel) {}
            Button("복구 실행", role: .destructive) {
                viewModel.recoverNetwork()
            }
        } message: {
            Text("Mac Wi-Fi가 돌아오지 않거나 터미널을 강제로 닫았을 때 사용하세요. 일반 종료는 [끄기]를 사용합니다.")
        }
        .alert("먼저 끄기", isPresented: $viewModel.showCloseWarning) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("USB 인터넷이 실행 중입니다. 앱을 닫기 전에 [끄기]로 정상 종료하세요.")
        }
    }

    private var statusHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 14, height: 14)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("jam-usb-internet")
                    .font(.headline)
                Text(viewModel.statusSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let error = viewModel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if viewModel.cliMissing {
                    Text("Galaxy USB Internet ON.command 를 fallback으로 사용할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
    }

    private var statusColor: Color {
        switch viewModel.status?.state {
        case .running:
            return .green
        case .needsRecover:
            return .red
        case .partial:
            return .orange
        case .idle, .none:
            return .gray
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: viewModel.startSystem) {
                Label("USB 인터넷 켜기", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(viewModel.cliMissing || viewModel.isBusy || viewModel.isSystemRunning)

            Button(action: viewModel.stopSystem) {
                Label("끄기", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.cliMissing || viewModel.isBusy)

            Button {
                viewModel.showRecoverConfirm = true
            } label: {
                Label("복구", systemImage: "lifepreserver.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(viewModel.cliMissing || viewModel.isBusy)
        }
    }

    private var warningBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("실행 중에는 이 앱을 닫지 마세요.", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("끌 때는 반드시 [끄기]를 사용하세요. Mac Wi-Fi가 안 돌아오면 [복구]를 누르세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var preflightSection: some View {
        if let doctor = viewModel.doctor {
            VStack(alignment: .leading, spacing: 6) {
                Text("시작 전 확인")
                    .font(.subheadline.weight(.semibold))
                ForEach(doctor.checks) { check in
                    HStack(spacing: 8) {
                        Image(systemName: check.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(check.ok ? .green : .red)
                        Text(checkLabel(check))
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func checkLabel(_ check: PreflightCheck) -> String {
        switch check.name {
        case "adb":
            return check.ok ? "ADB 설치됨" : check.message
        case "adb_authorized":
            return check.ok ? "Galaxy USB debugging 승인됨" : check.message
        case "sing_box":
            return check.ok ? "sing-box 설치됨" : check.message
        default:
            return check.message
        }
    }

    private var readerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $viewModel.selectedPanel) {
                ForEach(ReaderPanel.allCases) { panel in
                    Text(panel.title).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Text(viewModel.selectedPanel.title)
                    .font(.subheadline.weight(.semibold))
                if viewModel.selectedPanel != .log,
                   let fileName = viewModel.selectedPanel.docFileName {
                    Text("docs/\(fileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("전체 복사") {
                    viewModel.copyPanelText()
                }
                .buttonStyle(.link)
                .disabled(viewModel.panelText.isEmpty)
                if viewModel.selectedPanel == .log {
                    Button("지우기") {
                        viewModel.clearLogs()
                    }
                    .buttonStyle(.link)
                    .disabled(viewModel.logLines.isEmpty)
                }
            }

            LogTextEditor(
                text: viewModel.panelText,
                scrollToEndOnUpdate: viewModel.selectedPanel == .log
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
        .frame(maxHeight: .infinity)
    }

    private var footerBar: some View {
        HStack {
            Button("Mac 설정") {
                viewModel.showPanel(.macSetup)
            }
            .buttonStyle(.link)
            Button("Galaxy 설정") {
                viewModel.showPanel(.galaxySetup)
            }
            .buttonStyle(.link)
            Button("사용 방법") {
                viewModel.showPanel(.usage)
            }
            .buttonStyle(.link)
            Button("로그") {
                viewModel.showPanel(.log)
            }
            .buttonStyle(.link)
            Spacer()
            Button("상태 새로고침") {
                viewModel.refreshDoctor()
                viewModel.refreshStatus()
                viewModel.loadDocs()
            }
            .buttonStyle(.link)
        }
        .font(.caption)
    }
}
