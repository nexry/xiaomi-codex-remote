import SwiftUI
import AVFoundation
import CoreBluetooth

/// Daily status and controls for the native XiaomiCodexRemote bridge.
struct MainWindow: View {
    var state: AppState
    @State private var selectedPage: Page = .status
    @AppStorage(AppPreferences.hideDockIconKey) private var hideDockIcon = false

    private enum Page: String, CaseIterable, Identifiable {
        case status, keyMapping, settings, permissions, logs
        var id: Self { self }
        var title: String {
            switch self {
            case .status: return "状态与连接"
            case .keyMapping: return "按键设置"
            case .settings: return "偏好设置"
            case .permissions: return "权限"
            case .logs: return "日志"
            }
        }
        var icon: String {
            switch self {
            case .status: return "point.3.connected.trianglepath.dotted"
            case .keyMapping: return "keyboard.badge.ellipsis"
            case .settings: return "gearshape"
            case .permissions: return "lock.shield"
            case .logs: return "stethoscope"
            }
        }
    }

    private struct NextStep {
        let title: String
        let message: String
        let button: String?
        let action: (() -> Void)?
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 200)
            Divider()
            pageContent.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 800, height: 560)
        .onAppear { state.refreshPermissions() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Xiaomi Codex Remote").font(.title2.weight(.semibold))
                HStack(spacing: 7) {
                    Circle().fill(sidebarStatus.color).frame(width: 8, height: 8)
                    Text(sidebarStatus.label).font(.subheadline)
                }
                .foregroundStyle(sidebarStatus.color)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("连接状态：\(sidebarStatus.label)")
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 24)

            ForEach(Page.allCases) { page in
                Button { selectedPage = page } label: {
                    HStack(spacing: 11) {
                        Image(systemName: page.icon).frame(width: 20)
                        Text(page.title)
                        Spacer(minLength: 0)
                        if page != .settings && page != .keyMapping {
                            Circle().fill(status(for: page).color).frame(width: 7, height: 7)
                        }
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedPage == page ? Color.accentColor : Color.primary)
                .background(selectedPage == page ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("\(page.title)，\(status(for: page).label)")
                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                .padding(.horizontal, 10)
                .padding(.bottom, 3)
            }
            Spacer(minLength: 12)
            Text("关闭窗口后仍在菜单栏运行")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(18)
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    // MARK: - Page Content

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .status:
            ScrollView {
                statusPage
                    .frame(maxWidth: 750, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(28)
            }
        case .settings:
            ScrollView {
                settingsPage
                    .frame(maxWidth: 750, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(28)
            }
        case .keyMapping:
            KeyMappingPage(state: state)
                .frame(maxWidth: 750, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .clipped()
        case .permissions:
            ScrollView {
                permissionsPage
                    .frame(maxWidth: 750, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(28)
            }
        case .logs:
            logsPage
        }
    }

    // MARK: - Status Page

    private var statusPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("状态与连接").font(.largeTitle.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text(nextStep.title).font(.title3.weight(.semibold))
                Text(nextStep.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let button = nextStep.button, let action = nextStep.action {
                    Button(button, action: action)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    remoteCard.frame(maxWidth: .infinity)
                    chatGPTCard.frame(maxWidth: .infinity)
                }
                HStack(alignment: .top, spacing: 16) {
                    audioCard.frame(maxWidth: .infinity)
                    bridgeCard.frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Settings Page

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("偏好设置").font(.largeTitle.weight(.semibold))

            VStack(alignment: .leading, spacing: 16) {
                Text("通用").font(.headline)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("隐藏 Dock 图标")
                        Text("隐藏后仍可通过菜单栏图标打开应用。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("隐藏 Dock 图标", isOn: $hideDockIcon)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .fixedSize()
                        .onChange(of: hideDockIcon) { _, hidden in
                            AppPreferences.applyDockIconVisibility(
                                hidden: hidden,
                                activateWhenVisible: true
                            )
                        }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 16) {
                Text("遥控器与语音").font(.headline)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("音量拦截")
                        Text("开启后，按遥控器的音量键不会改变 Mac 系统的音量。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state.volumeInterceptor.isEnabled {
                        Label("已启用", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("启用") {
                            state.volumeInterceptor.requestAccessibility()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                state.volumeInterceptor.start()
                            }
                        }
                    }
                }

                Divider()

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MiCodexRemote 虚拟声卡")
                        Text("用于接收遥控器麦克风的声音。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state.driverManager.status == .notInstalled || driverInstallFailed {
                        Button("安装驱动") { state.installDriver() }
                    } else if state.driverManager.status == .installing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("已安装").foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 16) {
                Text("系统与连接").font(.headline)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("遥控连接服务")
                        Text("负责连接遥控器与 ChatGPT，让遥控按键生效。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    switch state.bridge.state {
                    case .running:
                        Text("正常").foregroundStyle(.secondary)
                    case .starting:
                        ProgressView().controlSize(.small)
                    case .stopped:
                        Button("启动连接服务") { state.bridge.start() }
                    case .failed:
                        Button("重启连接服务") { state.bridge.restart() }
                    }
                }

                Divider()

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ChatGPT 遥控版")
                        Text(chatGPTCompatibilityDescription)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if state.chatGPTLauncher.compatibilityState == .preparing {
                        ProgressView().controlSize(.small)
                    } else if case .ready = state.chatGPTLauncher.compatibilityState {
                        HStack {
                            Button("在 Finder 中显示") { state.revealChatGPTDockEntry() }
                            Button("打开") { state.launchChatGPT() }
                        }
                    } else if let label = chatGPTCompatibilityActionLabel {
                        Button(label) { state.prepareChatGPTCompatibility() }
                    }
                }
            }
            .padding()
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Permissions Page

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("权限").font(.largeTitle.weight(.semibold))
            Text("检查应用正常工作所需的系统权限，并在授权后重新检测状态。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                        permissionRow(
                            icon: "antenna.radiowaves.left.and.right",
                            title: "蓝牙",
                            detail: "用于寻找已配对的遥控器并接收语音数据。首次连接时 macOS 会请求授权。",
                            granted: state.bluetoothAuthorization == .allowedAlways,
                            status: bluetoothPermissionStatus,
                            actionTitle: "打开系统设置",
                            action: state.openBluetoothPrivacySettings
                        )
                        Divider().padding(.leading, 54)
                        permissionRow(
                            icon: "keyboard",
                            title: "输入监控",
                            detail: "接收遥控器按键所必需。允许 Xiaomi Codex Remote 后返回应用重新检测。",
                            granted: state.inputMonitoringAccess == .granted,
                            status: inputMonitoringPermissionStatus,
                            actionTitle: state.inputMonitoringAccess == .unknown ? "请求权限" : "打开系统设置",
                            action: state.inputMonitoringAccess == .unknown
                                ? state.requestInputMonitoringPermission : state.openInputMonitoringSettings
                        )
                        Divider().padding(.leading, 54)
                        permissionRow(
                            icon: "mic",
                            title: "麦克风",
                            detail: "应用启动时请求音频权限；遥控器语音仍需蓝牙连接和虚拟音频设备。",
                            granted: state.microphoneAuthorization == .authorized,
                            status: microphonePermissionStatus,
                            actionTitle: state.microphoneAuthorization == .notDetermined ? "请求权限" : "打开系统设置",
                            action: state.requestMicrophonePermission
                        )
                        Divider().padding(.leading, 54)
                        permissionRow(
                            icon: "hand.point.up.left",
                            title: "辅助功能（可选）",
                            detail: "启用音量拦截时使用，避免遥控器音量键同时改变 Mac 系统音量。",
                            granted: state.accessibilityGranted,
                            status: state.accessibilityGranted ? "已允许" : "未允许",
                            actionTitle: state.accessibilityGranted ? "打开系统设置" : "请求权限",
                            action: state.accessibilityGranted
                                ? state.openAccessibilitySettings : state.requestAccessibilityPermission
                        )
            }
            .padding(.horizontal, 16)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))

            Button("重新检测权限状态") { state.refreshAfterReturningToApp() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - Logs Page

    private var logsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("日志").font(.largeTitle.weight(.semibold))
                Text("查看连接、按键、语音和 ChatGPT 桥接的诊断与活动日志。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(28)

            Divider()

            LogView(lines: state.logLines)
        }
    }

    // MARK: - Permission Helpers

    private func permissionRow(
        icon: String,
        title: String,
        detail: String,
        granted: Bool,
        status: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Label(status, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(granted ? Color.green : Color.orange)
                .frame(width: 90, alignment: .leading)
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .frame(width: 116)
        }
        .padding(.vertical, 14)
    }

    private var bluetoothPermissionStatus: String {
        switch state.bluetoothAuthorization {
        case .allowedAlways: return "已允许"
        case .denied: return "未允许"
        case .restricted: return "受限制"
        case .notDetermined: return "待授权"
        @unknown default: return "待检测"
        }
    }

    private var inputMonitoringPermissionStatus: String {
        switch state.inputMonitoringAccess {
        case .granted: return "已允许"
        case .denied: return "未允许"
        case .unknown: return "待授权"
        }
    }

    private var microphonePermissionStatus: String {
        switch state.microphoneAuthorization {
        case .authorized: return "已允许"
        case .denied: return "未允许"
        case .restricted: return "受限制"
        case .notDetermined: return "待授权"
        @unknown default: return "待检测"
        }
    }

    // MARK: - Cards Implementation

    private var remoteCard: some View {
        StatusCard(
            icon: "gamecontroller.fill",
            title: "遥控器",
            status: remoteStatus,
            details: remoteDetails,
            actionLabel: remotePermissionNeeded ? "打开输入监控设置" : "重新检测",
            action: remoteAction
        )
    }

    private var remoteStatus: StatusCard.Status {
        switch state.hidStatus {
        case .connected: return .good("已连接")
        case .permissionRequired: return .warning("需要输入监控权限")
        case .permissionDenied: return .error("输入监控被拒绝")
        case .searching: return .inactive("等待遥控器")
        case .failed(let message): return .error(message)
        case .stopped: return .inactive("检测已停止")
        }
    }

    private var remoteDetails: [String] {
        var details: [String] = []
        if remoteConnected {
            details.append(state.remoteName ?? "已连接的遥控器")
            if let battery = state.remoteBattery {
                details.append("电量: \(battery)%")
            }
        } else {
            details.append(remotePermissionNeeded ? "授权后返回应用重新检测" : "等待已配对的遥控器连接")
        }
        return details
    }

    private var audioCard: some View {
        StatusCard(
            icon: "mic.fill",
            title: "音频设备",
            status: audioStatus,
            details: audioDetails,
            actionLabel: audioActionLabel,
            action: audioAction
        )
    }

    private var audioStatus: StatusCard.Status {
        if state.driverManager.status == .notInstalled {
            return .error("驱动未安装")
        } else if state.driverManager.status == .installing {
            return .warning("正在安装驱动")
        } else if case .failed(let msg) = state.driverManager.status {
            return .error("安装失败：\(msg)")
        } else if state.isVoiceStreaming {
            return .warning("正在传输")
        } else if state.audioReady {
            return .good("设备就绪")
        } else {
            return .error(state.audioOutput.selectedDevice == nil ? "未找到音频设备" : "音频设备未运行")
        }
    }

    private var audioDetails: [String] {
        switch state.driverManager.status {
        case .notInstalled: return ["需要安装 MiCodexRemote 音频驱动"]
        case .installing: return ["按系统提示完成安装"]
        case .failed: return ["请重试安装"]
        case .installed: return [state.audioOutput.selectedDevice?.name ?? "未选择音频设备"]
        }
    }

    private var audioActionLabel: String? {
        switch state.driverManager.status {
        case .notInstalled, .failed:
            return "安装驱动"
        case .installing:
            return nil
        case .installed:
            return state.audioReady ? nil : "重新检测"
        }
    }

    private var audioAction: (() -> Void)? {
        switch state.driverManager.status {
        case .notInstalled, .failed:
            return { self.state.installDriver() }
        case .installing:
            return nil
        case .installed:
            if state.audioReady {
                return nil
            } else {
                return {
                    self.state.driverManager.refresh()
                    _ = self.state.audioOutput.configure()
                    self.state.audioReady = self.state.audioOutput.isReady
                }
            }
        }
    }

    private var bridgeCard: some View {
        StatusCard(
            icon: "cable.connector",
            title: "遥控连接服务",
            status: bridgeStatus,
            details: bridgeDetails,
            actionLabel: bridgeActionLabel,
            action: bridgeAction
        )
    }

    private var bridgeStatus: StatusCard.Status {
        switch state.bridge.state {
        case .running: return .good("正常")
        case .starting: return .warning("启动中")
        case .failed(let msg): return .error("异常: \(msg)")
        case .stopped: return .inactive("未启动")
        }
    }

    private var bridgeDetails: [String] {
        ["负责连接遥控器与 ChatGPT，让遥控按键生效。"]
    }

    private var bridgeActionLabel: String? {
        switch state.bridge.state {
        case .running, .starting: return nil
        case .stopped: return "启动连接服务"
        case .failed: return "重启连接服务"
        }
    }

    private var bridgeAction: (() -> Void)? {
        switch state.bridge.state {
        case .failed:
            return { state.bridge.restart() }
        case .stopped:
            return { state.bridge.start() }
        case .running, .starting:
            return nil
        }
    }

    private var chatGPTCard: some View {
        StatusCard(
            icon: "bubble.left.fill",
            title: "ChatGPT 遥控版",
            status: chatGPTStatus,
            details: chatGPTDetails,
            actionLabel: chatGPTCardActionLabel,
            action: chatGPTCardAction
        )
    }

    private var chatGPTStatus: StatusCard.Status {
        switch state.chatGPTLauncher.compatibilityState {
        case .checking: return .inactive("正在检查")
        case .sourceMissing: return .error("未找到官方应用")
        case .needsPreparation: return .warning("需要准备")
        case .needsUpdate: return .warning("需要更新遥控支持")
        case .needsRepair: return .warning("需要修复")
        case .preparing: return .warning("正在准备")
        case let .failed(message): return .error(message)
        case .ready:
            switch state.chatGPTLauncher.launchState {
            case .connected: return .good("已连接")
            case .launching: return .warning("正在打开")
            case .waitingForShim: return .warning("等待 ChatGPT 连接")
            case let .failed(message): return .error(message)
            case .idle: return .inactive("遥控版已就绪")
            }
        }
    }

    private var chatGPTDetails: [String] {
        switch state.chatGPTLauncher.compatibilityState {
        case let .ready(version):
            return ["ChatGPT 遥控版 · \(version)", "可在 Finder 中拖入 Dock"]
        case let .needsUpdate(installed, source):
            return ["遥控版 \(installed)", "官方版本 \(source)"]
        case let .needsRepair(reason): return [reason]
        case let .needsPreparation(version): return ["官方版本 \(version)"]
        case .sourceMissing: return ["请先安装官方 ChatGPT.app"]
        case .preparing: return ["正在复制、配置并验证应用"]
        case let .failed(message): return [message]
        case .checking: return ["正在检查版本和遥控支持"]
        }
    }

    private var chatGPTCompatibilityDescription: String {
        switch state.chatGPTLauncher.compatibilityState {
        case .checking: return "正在检查官方应用与遥控版。"
        case .sourceMissing: return "未找到官方 ChatGPT.app。"
        case .needsPreparation: return "为了让遥控器控制 ChatGPT，我们会创建一个支持遥控的独立副本，不会修改原版。使用遥控器时，请打开「ChatGPT 遥控版」。"
        case .needsUpdate: return "官方 ChatGPT 已更新，需要同步更新遥控支持。"
        case .needsRepair: return "遥控支持需要修复，请点击下方按钮重新设置。"
        case .preparing: return "正在复制、配置并验证遥控版，请稍候。"
        case .ready: return "遥控版位于“应用程序”目录；显示后可将它拖到 Dock。"
        case let .failed(message): return message
        }
    }

    private var chatGPTCompatibilityActionLabel: String? {
        switch state.chatGPTLauncher.compatibilityState {
        case .needsPreparation: return "设置遥控支持"
        case .needsUpdate: return "更新遥控支持"
        case .needsRepair, .failed: return "修复遥控支持"
        default: return nil
        }
    }

    private var chatGPTCardActionLabel: String? {
        if let label = chatGPTCompatibilityActionLabel { return label }
        guard case .ready = state.chatGPTLauncher.compatibilityState,
              state.bridge.state == .running else { return nil }
        return "打开 ChatGPT 遥控版"
    }

    private var chatGPTCardAction: (() -> Void)? {
        if chatGPTCompatibilityActionLabel != nil { return { state.prepareChatGPTCompatibility() } }
        guard case .ready = state.chatGPTLauncher.compatibilityState,
              state.bridge.state == .running else { return nil }
        return { state.launchChatGPT() }
    }

    // MARK: - State Properties & Logic

    private var remoteConnected: Bool {
        if case .connected = state.hidStatus { return true }
        return false
    }

    private var remotePermissionNeeded: Bool {
        state.hidStatus == .permissionRequired || state.hidStatus == .permissionDenied
    }

    private var remoteAction: () -> Void {
        if remotePermissionNeeded { return state.openInputMonitoringSettings }
        return {
            state.hidMonitor.stop()
            state.hidMonitor.start()
        }
    }

    private var sidebarStatus: StatusCard.Status {
        if remoteConnected && state.bridge.shimConnected { return .good("按键已连接") }
        if remotePermissionNeeded { return .error("需要输入监控权限") }
        if case .failed = state.bridge.state { return .error("连接服务异常") }
        return .inactive("等待连接")
    }

    private func status(for page: Page) -> StatusCard.Status {
        switch page {
        case .status: return sidebarStatus
        case .keyMapping: return .inactive("按键配置")
        case .settings: return .inactive("设置")
        case .permissions:
            return state.bluetoothAuthorization == .allowedAlways &&
                state.inputMonitoringAccess == .granted &&
                state.microphoneAuthorization == .authorized
                ? .good("已授权") : .warning("查看权限")
        case .logs: return .inactive("活动日志")
        }
    }

    private var nextStep: NextStep {
        if remotePermissionNeeded {
            return NextStep(title: "允许输入监控", message: "Xiaomi Codex Remote 需要这项权限才能接收遥控器按键。",
                            button: "查看权限", action: { selectedPage = .permissions })
        }
        if case .failed = state.hidStatus {
            return NextStep(title: "重新检测遥控器", message: "按键接收遇到问题，请重新检测。",
                            button: "重新检测", action: remoteAction)
        }
        switch state.chatGPTLauncher.compatibilityState {
        case .sourceMissing:
            return NextStep(title: "安装 ChatGPT", message: "需要先安装官方 ChatGPT.app，才能创建遥控版。",
                            button: nil, action: nil)
        case .needsPreparation:
            return NextStep(title: "设置遥控支持", message: "创建支持遥控的独立副本，不会修改原版。使用遥控器时，请打开「ChatGPT 遥控版」。",
                            button: "设置遥控支持", action: { state.prepareChatGPTCompatibility() })
        case .needsUpdate:
            return NextStep(title: "更新遥控支持", message: "官方 ChatGPT 已更新，请同步遥控版后继续使用。",
                            button: "更新遥控支持", action: { state.prepareChatGPTCompatibility() })
        case .needsRepair, .failed:
            return NextStep(title: "修复遥控支持", message: chatGPTCompatibilityDescription,
                            button: "修复遥控支持", action: { state.prepareChatGPTCompatibility() })
        case .preparing:
            return NextStep(title: "正在设置遥控支持", message: "正在复制、配置并验证 ChatGPT，请保持 Xiaomi Codex Remote 运行。",
                            button: nil, action: nil)
        case .checking, .ready:
            break
        }
        if !remoteConnected {
            return NextStep(title: "连接遥控器", message: "等待已配对的遥控器连接；连接后按键状态会自动更新。",
                            button: nil, action: nil)
        }
        if state.bridge.state != .running {
            return NextStep(title: "遥控连接服务", message: "负责连接遥控器与 ChatGPT，让遥控按键生效。",
                            button: bridgeActionLabel, action: bridgeAction)
        }
        if !state.bridge.shimConnected {
            return NextStep(title: "连接 ChatGPT", message: "打开 ChatGPT 遥控版；连接成功后才会显示为已连接。",
                            button: "打开 ChatGPT 遥控版", action: { state.launchChatGPT() })
        }
        if state.driverManager.status == .notInstalled || driverInstallFailed {
            return NextStep(title: "准备音频设备", message: "安装音频驱动后才能使用遥控器语音。",
                            button: "前往设置安装", action: { selectedPage = .settings })
        }
        if !state.audioReady && state.driverManager.status != .installing {
            return NextStep(title: "检测音频设备", message: "当前音频设备尚未就绪。",
                            button: "前往设置检查", action: { selectedPage = .settings })
        }
        return NextStep(title: "连接已就绪", message: "遥控器按键、音频设备与 ChatGPT 连接均已畅通。",
                        button: nil, action: nil)
    }

    private var driverInstallFailed: Bool {
        if case .failed = state.driverManager.status { return true }
        return false
    }
}
