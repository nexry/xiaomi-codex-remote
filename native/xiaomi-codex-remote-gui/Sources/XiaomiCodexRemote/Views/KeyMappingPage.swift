import AppKit
import SwiftUI
import Observation

private struct RemoteKeyOutlineShape: Shape {
    let keyID: String

    // Coordinates use the supplied 342 × 898 px image.
    static func center(for keyID: String) -> CGPoint {
        switch keyID {
        case "power": return CGPoint(x: 86, y: 91)
        case "voice": return CGPoint(x: 258, y: 91)
        case "up": return CGPoint(x: 172, y: 190)
        case "down": return CGPoint(x: 172, y: 402)
        case "left": return CGPoint(x: 66, y: 296)
        case "right": return CGPoint(x: 278, y: 296)
        case "back": return CGPoint(x: 103, y: 500)
        case "home": return CGPoint(x: 103, y: 627)
        case "menu": return CGPoint(x: 103, y: 754)
        case "volume_up": return CGPoint(x: 241, y: 500)
        case "volume_down": return CGPoint(x: 241, y: 627)
        case "tv": return CGPoint(x: 241, y: 754)
        default: return CGPoint(x: 172, y: 296)
        }
    }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 342, rect.height / 898)
        let origin = CGPoint(x: rect.midX - 171 * scale, y: rect.midY - 449 * scale)
        func point(_ value: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + value.x * scale, y: origin.y + value.y * scale)
        }
        let direction: Double?
        switch keyID {
        case "up": direction = -90
        case "right": direction = 0
        case "down": direction = 90
        case "left": direction = 180
        default: direction = nil
        }
        if let direction {
            // Exact cubic outline from Resources/remote_arrow_btn.svg (83 × 35 pt).
            // Rotate its upper sector around the center of the directional ring.
            let rotation = (direction + 90) * .pi / 180
            func svgPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                let dx = x - 41.347
                let dy = y - 65
                return point(CGPoint(
                    x: 172 + 2 * (dx * cos(rotation) - dy * sin(rotation)),
                    y: 296 + 2 * (dx * sin(rotation) + dy * cos(rotation))
                ))
            }
            var path = Path()
            path.move(to: svgPoint(1.876, 13.966))
            path.addCurve(to: svgPoint(41.347, 0.5), control1: svgPoint(7.763, 9.454), control2: svgPoint(21.896, 0.5))
            path.addCurve(to: svgPoint(80.818, 13.966), control1: svgPoint(60.798, 0.5), control2: svgPoint(74.932, 9.454))
            path.addCurve(to: svgPoint(81.128, 19.37), control1: svgPoint(82.558, 15.298), control2: svgPoint(82.635, 17.78))
            path.addLine(to: svgPoint(68.674, 32.517))
            path.addCurve(to: svgPoint(62.632, 32.954), control1: svgPoint(67.125, 34.151), control2: svgPoint(64.492, 34.223))
            path.addCurve(to: svgPoint(41.347, 26.5), control1: svgPoint(58.732, 30.293), control2: svgPoint(51.409, 26.5))
            path.addCurve(to: svgPoint(20.062, 32.954), control1: svgPoint(31.285, 26.5), control2: svgPoint(23.962, 30.293))
            path.addCurve(to: svgPoint(14.021, 32.517), control1: svgPoint(18.202, 34.224), control2: svgPoint(15.569, 34.151))
            path.addLine(to: svgPoint(1.566, 19.37))
            path.addCurve(to: svgPoint(1.876, 13.966), control1: svgPoint(0.059, 17.78), control2: svgPoint(0.137, 15.298))
            path.closeSubpath()
            return path
        }
        let center = point(Self.center(for: keyID))
        let radius: CGFloat
        switch keyID {
        case "power", "voice": radius = 33
        case "ok": radius = 67
        default: radius = 47
        }
        let topButton = keyID == "power" || keyID == "voice"
        // Preserve the existing top-button center's 0.5 pt vertical adjustment.
        return Path(ellipseIn: CGRect(x: center.x - radius * scale,
                                      y: center.y - radius * scale + (topButton ? scale : 0),
                                      width: radius * 2 * scale,
                                      height: radius * 2 * scale))
    }
}

private struct RemoteKeyHotspotStyle: ButtonStyle {
    let keyID: String
    let configured: Bool
    let symbol: String

    func makeBody(configuration: Configuration) -> some View {
        let outline = RemoteKeyOutlineShape(keyID: keyID)
        let blue = Color(red: 0.19, green: 0.53, blue: 0.96)
        let gray = Color(red: 0.73, green: 0.73, blue: 0.73)
        let center = RemoteKeyOutlineShape.center(for: keyID)
        let topButton = keyID == "power" || keyID == "voice"
        let directionalControl = ["up", "down", "left", "right", "ok"].contains(keyID)
        configuration.label
            .overlay {
                if configuration.isPressed {
                    outline.fill(LinearGradient(
                        colors: [Color(red: 0.42, green: 0.65, blue: 1), blue, Color(red: 0.12, green: 0.35, blue: 0.78)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                }
            }
            .overlay {
                outline.stroke(
                    configured || configuration.isPressed ? blue : gray,
                    style: StrokeStyle(
                        lineWidth: 1,
                        dash: configuration.isPressed || configured ? [] : [3, 3]
                    )
                )
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: topButton ? 14 : 16, weight: .regular))
                    .foregroundStyle(configuration.isPressed ? Color.white : configured ? blue : gray)
                    .shadow(color: configuration.isPressed ? Color.white.opacity(0.34) : .clear, radius: 4)
                    .opacity(directionalControl && !configuration.isPressed ? 0 : 1)
                    .position(x: center.x / 2, y: center.y / 2)
                    .allowsHitTesting(false)
            }
    }
}

@Observable
final class BindingEditorSession: Identifiable {
    let id: String
    let originalBinding: XiaomiBinding?
    var binding: XiaomiBinding?
    var pendingBinding: XiaomiBinding?

    init(id: String, binding: XiaomiBinding?) {
        self.id = id
        originalBinding = binding
        self.binding = binding
    }

    var hasChanges: Bool { binding != originalBinding }
    var isVoiceLocked: Bool { id == "voice" }
}

struct KeyMappingPage: View {
    var state: AppState

    @State private var editingSession: BindingEditorSession?
    @State private var errorMessage: String?
    @State private var showsRestoreConfirmation = false

    private struct RemoteKey: Identifiable {
        let id: String
        let title: String
        let symbol: String
    }

    private struct BindingTarget: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let binding: XiaomiBinding
    }

    private static let remoteKeys = [
        RemoteKey(id: "power", title: "电源", symbol: "power"),
        RemoteKey(id: "up", title: "上", symbol: "chevron.up"),
        RemoteKey(id: "left", title: "左", symbol: "chevron.left"),
        RemoteKey(id: "ok", title: "确认", symbol: "checkmark"),
        RemoteKey(id: "right", title: "右", symbol: "chevron.right"),
        RemoteKey(id: "down", title: "下", symbol: "chevron.down"),
        RemoteKey(id: "back", title: "返回", symbol: "chevron.left"),
        RemoteKey(id: "home", title: "主页", symbol: "house"),
        RemoteKey(id: "menu", title: "菜单", symbol: "line.3.horizontal"),
        RemoteKey(id: "volume_down", title: "音量−", symbol: "minus"),
        RemoteKey(id: "volume_up", title: "音量+", symbol: "plus"),
        RemoteKey(id: "voice", title: "语音", symbol: "mic"),
        RemoteKey(id: "tv", title: "TV", symbol: "display"),
    ]
    private static let remoteDisplaySize = CGSize(width: 171, height: 449)

    private static let agentTargets = [0, 1, 2, 3, 4, 5].map { (index: Int) in
        BindingTarget(
            id: "AG0\(index)",
            title: "AG0\(index)",
            detail: "Micro 键位",
            symbol: "person.crop.square",
            binding: .init(kind: .key, keycode: "AG0\(index)", agent: index, angle: nil)
        )
    }

    private static let actionTargets = [
        BindingTarget(id: "ACT06", title: "ACT06", detail: "Micro 键位", symbol: "bolt", binding: .init(kind: .key, keycode: "ACT06", agent: nil, angle: nil)),
        BindingTarget(id: "ACT07", title: "ACT07", detail: "Micro 键位", symbol: "checkmark.circle", binding: .init(kind: .key, keycode: "ACT07", agent: nil, angle: nil)),
        BindingTarget(id: "ACT08", title: "ACT08", detail: "Micro 键位", symbol: "xmark.circle", binding: .init(kind: .key, keycode: "ACT08", agent: nil, angle: nil)),
        BindingTarget(id: "ACT09", title: "ACT09", detail: "Micro 键位", symbol: "arrow.triangle.branch", binding: .init(kind: .key, keycode: "ACT09", agent: nil, angle: nil)),
        BindingTarget(id: "ACT10", title: "ACT10", detail: "Micro 键位", symbol: "mic", binding: .init(kind: .key, keycode: "ACT10", agent: nil, angle: nil)),
        BindingTarget(id: "ACT12", title: "ACT12", detail: "Micro 键位", symbol: "paperplane", binding: .init(kind: .key, keycode: "ACT12", agent: nil, angle: nil)),
    ]

    private static let controlTargets = [
        BindingTarget(id: "ENC_CC", title: "逆时针", detail: "ENC_CC · act 2", symbol: "arrow.counterclockwise", binding: .init(kind: .rotate, keycode: "ENC_CC", agent: nil, angle: nil)),
        BindingTarget(id: "ENC_CLK", title: "旋钮按压", detail: "ENC_CLK", symbol: "circle.inset.filled", binding: .init(kind: .key, keycode: "ENC_CLK", agent: nil, angle: nil)),
        BindingTarget(id: "ENC_CW", title: "顺时针", detail: "ENC_CW · act 2", symbol: "arrow.clockwise", binding: .init(kind: .rotate, keycode: "ENC_CW", agent: nil, angle: nil)),
        BindingTarget(id: "JOY_UP", title: "摇杆上", detail: "角度 0.75", symbol: "arrow.up", binding: .init(kind: .joystick, keycode: nil, agent: nil, angle: 0.75)),
        BindingTarget(id: "JOY_LEFT", title: "摇杆左", detail: "角度 0.5", symbol: "arrow.left", binding: .init(kind: .joystick, keycode: nil, agent: nil, angle: 0.5)),
        BindingTarget(id: "JOY_RIGHT", title: "摇杆右", detail: "角度 0", symbol: "arrow.right", binding: .init(kind: .joystick, keycode: nil, agent: nil, angle: 0.0)),
        BindingTarget(id: "JOY_DOWN", title: "摇杆下", detail: "角度 0.25", symbol: "arrow.down", binding: .init(kind: .joystick, keycode: nil, agent: nil, angle: 0.25)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("按键设置").font(.largeTitle.weight(.semibold))
            Text("点击左侧遥控器上的按钮，查看或设置对应的 Codex Micro 按键。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 32) {
                remotePanel.frame(width: 190)
                remoteSummaryPanel
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editingSession) { session in
            bindingEditorSheet(for: session)
        }
        .confirmationDialog("恢复默认设置？", isPresented: $showsRestoreConfirmation) {
            Button("恢复默认", role: .destructive, action: restoreDefaults)
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有自定义按键设置都会恢复为默认值。Power 和语音键的固定用途不变。")
        }
        .alert("无法保存按键设置", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var remoteSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("小米蓝牙遥控器2").font(.title3.weight(.semibold))
                Label(
                    state.remoteConnected ? "已连接" : "未连接",
                    systemImage: state.remoteConnected ? "checkmark.circle.fill" : "circle.dashed"
                )
                .foregroundStyle(state.remoteConnected ? Color.green : Color.secondary)
                Text("\(boundCount) 个已设置 · \(configurableKeys.count - boundCount) 个未设置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("固定按键").font(.subheadline.weight(.semibold))
                Label("Power：打开 ChatGPT 遥控版", systemImage: "power")
                Label("语音：按住说话，松开结束", systemImage: "mic")
            }
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)

            Text("语音需在 ChatGPT 中将 ACT10 设置为对应的语音操作。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("可在未连接时设置，保存后生效。具体按键功能由 ChatGPT 决定。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("恢复默认设置") { showsRestoreConfirmation = true }
            }
                .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(minHeight: 300, alignment: .topLeading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }

    private func bindingEditorSheet(for session: BindingEditorSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(remoteKeyTitle(session.id)).font(.title3.weight(.semibold))
                    Spacer()
                    Button { editingSession = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("关闭，不保存更改")
                    .help("关闭，不保存更改")
                }
                Text(Self.currentBindingDescription(session.originalBinding))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)

            Divider()

            codexPanel(session: session)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            HStack {
                Button("清除绑定") { session.binding = nil }
                    .disabled(session.isVoiceLocked || session.binding == nil)
                Spacer()
                Button("保存更改") { save(session: session) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!session.hasChanges || session.isVoiceLocked)
            }
            .padding(16)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("这个键位已经被占用", isPresented: Binding(
            get: { session.pendingBinding != nil },
            set: { if !$0 { session.pendingBinding = nil } }
        )) {
            Button("仍然绑定") {
                session.binding = session.pendingBinding
                session.pendingBinding = nil
            }
            Button("取消", role: .cancel) { session.pendingBinding = nil }
        } message: {
            if let pending = session.pendingBinding {
                Text("\(bindingTitle(pending)) 已绑定到\(owners(of: pending, excluding: session.id).joined(separator: "、"))。允许多个遥控器按键使用同一个目标。")
            }
        }
    }

    private var remotePanel: some View {
        VStack(spacing: 0) {
            ZStack {
                remoteProductImage
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)

                ForEach(Self.remoteKeys) { key in
                    remoteHotspot(key.id)
                        .zIndex(key.id == "ok" ? 1 : 0)
                }
            }
            .frame(width: Self.remoteDisplaySize.width, height: Self.remoteDisplaySize.height)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
        }
    }

    private func codexPanel(session: BindingEditorSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Codex Micro").font(.headline)
            Text("选择对应按键。点击旋钮或摇杆，可展开更多选项。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if session.isVoiceLocked {
                Label("语音键固定 ACT10，按住开启麦克风", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .help("不可修改或清除绑定。松开关闭遥控器麦克风；ACT10 在 ChatGPT 中的行为由其配置决定。")
            }

            microImagePanel(session: session)
                .frame(maxWidth: .infinity, alignment: .center)

        }
        .padding(12)
        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func microImagePanel(session: BindingEditorSession) -> some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 480
            ZStack(alignment: .topLeading) {
                microProductImage.resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fit)

                controlMenu("旋钮", targets: Array(Self.controlTargets.prefix(3)), joystick: false, session: session)
                    .frame(width: 94 * scale, height: 94 * scale)
                    .position(x: 73 * scale, y: 74 * scale)
                controlMenu("摇杆", targets: Array(Self.controlTargets.dropFirst(3)), joystick: true, session: session)
                    .frame(width: 94 * scale, height: 94 * scale)
                    .position(x: 407 * scale, y: 75 * scale)

                ForEach(Array(Self.agentTargets.enumerated()), id: \.element.id) { index, target in
                    let firstRow = index < 2
                    let column = firstRow ? index + 1 : index - 2
                    targetButton(target, session: session)
                        .frame(width: 102 * scale, height: 102 * scale)
                        .position(x: CGFloat(73 + column * 111) * scale,
                                  y: CGFloat(firstRow ? 74 : 185) * scale)
                }
                ForEach(Array(Self.actionTargets.prefix(4).enumerated()), id: \.element.id) { index, target in
                    targetButton(target, session: session)
                        .frame(width: 102 * scale, height: 102 * scale)
                        .position(x: CGFloat(73 + index * 111) * scale, y: 296 * scale)
                }
                targetButton(Self.actionTargets[4], session: session)
                    .frame(width: 212 * scale, height: 102 * scale)
                    .position(x: 239.5 * scale, y: 407 * scale)
                targetButton(Self.actionTargets[5], session: session)
                    .frame(width: 102 * scale, height: 102 * scale)
                    .position(x: 407 * scale, y: 407 * scale)
            }
        }
        .frame(width: 240, height: 240)
    }

    private var microProductImage: Image {
        guard let url = Bundle.main.url(forResource: "CodexMicro", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return Image(systemName: "keyboard")
        }
        return Image(nsImage: image)
    }

    private func controlMenu(_ title: String, targets: [BindingTarget], joystick: Bool, session: BindingEditorSession) -> some View {
        let selected = targets.contains { $0.binding == session.binding }
        return Menu {
            ForEach(targets) { target in
                Button {
                    chooseTarget(target, session: session)
                } label: {
                    Label("\(target.title) · \(target.detail)", systemImage: session.binding == target.binding ? "checkmark" : target.symbol)
                }
            }
        } label: {
            Color.clear
                .frame(width: 47, height: 47)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 47, height: 47)
        // Draw outside the native menu label so AppKit cannot collapse or
        // replace the selection outline when presenting the menu control.
        .overlay {
            if joystick {
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                    }
                    .allowsHitTesting(false)
            } else {
                Circle()
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
                    .overlay {
                        Circle().strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                    }
                    .allowsHitTesting(false)
            }
        }
        .disabled(session.isVoiceLocked)
        .help(selected ? "\(title) · \(bindingTitle(session.binding))" : "\(title) · 点击选择操作")
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "已选择：\(bindingTitle(session.binding))" : "未选择")
    }

    private var remoteProductImage: Image {
        guard let url = Bundle.main.url(forResource: "XiaomiRemote", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return Image(systemName: "av.remote.fill")
        }
        return Image(nsImage: image)
    }

    private func remoteHotspot(_ keyID: String) -> some View {
        let configured = keyID == "power" || binding(for: keyID) != nil
        let outline = RemoteKeyOutlineShape(keyID: keyID)
        return Button {
            if keyID == "power" {
                let alert = NSAlert()
                alert.messageText = "打开 ChatGPT 遥控版"
                alert.informativeText = "Power 是固定启动键，不参与 Micro 映射。按遥控器 Power 键会自动设置并打开遥控版；首次使用会请求确认退出普通版 ChatGPT。"
                alert.addButton(withTitle: "好")
                alert.runModal()
                return
            }
            editingSession = BindingEditorSession(id: keyID, binding: binding(for: keyID))
        } label: {
            outline
                .fill(Color.clear)
                .contentShape(outline)
        }
        .buttonStyle(RemoteKeyHotspotStyle(
            keyID: keyID,
            configured: configured,
            symbol: Self.remoteKeys.first(where: { $0.id == keyID })?.symbol ?? "circle"
        ))
        .frame(width: Self.remoteDisplaySize.width, height: Self.remoteDisplaySize.height)
        .offset(y: -1)
        .help(keyID == "power" ? "Power · 打开 ChatGPT 遥控版（固定）" : "\(remoteKeyTitle(keyID)) · \(bindingTitle(binding(for: keyID)))")
        .accessibilityLabel(keyID == "power" ? "Power，打开 ChatGPT 遥控版，固定" : "\(remoteKeyTitle(keyID))，\(bindingTitle(binding(for: keyID)))")
    }

    private func targetButton(_ target: BindingTarget, session: BindingEditorSession) -> some View {
        let selected = session.binding == target.binding
        return Button {
            chooseTarget(target, session: session)
        } label: {
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(session.isVoiceLocked)
        .help("\(target.title) · \(target.detail)\(owners(of: target.binding, excluding: session.id).isEmpty ? "" : " · 已绑定：" + owners(of: target.binding, excluding: session.id).joined(separator: "、"))")
        .accessibilityLabel(target.title)
        .accessibilityValue(selected ? "已选择" : "未选择")
    }

    private func chooseTarget(_ target: BindingTarget, session: BindingEditorSession) {
        guard !session.isVoiceLocked else { return }
        if owners(of: target.binding, excluding: session.id).isEmpty || session.binding == target.binding {
            session.binding = target.binding
        } else {
            session.pendingBinding = target.binding
        }
    }

    private var configurableKeys: [RemoteKey] {
        Self.remoteKeys.filter { $0.id != "power" && $0.id != "voice" }
    }
    private var boundCount: Int { configurableKeys.filter { binding(for: $0.id) != nil }.count }

    private func binding(for key: String) -> XiaomiBinding? {
        guard let stored = state.keyMapping[key] else { return nil }
        return stored
    }

    private func owners(of binding: XiaomiBinding, excluding selectedKey: String) -> [String] {
        Self.remoteKeys.compactMap { key in
            guard key.id != selectedKey, self.binding(for: key.id) == binding else { return nil }
            return key.title
        }
    }

    private func remoteKeyTitle(_ id: String) -> String {
        Self.remoteButtonTitle(id)
    }

    static func remoteButtonTitle(_ id: String) -> String {
        switch id {
        case "up": return "上方向键"
        case "down": return "下方向键"
        case "left": return "左方向键"
        case "right": return "右方向键"
        case "ok": return "确认键"
        case "power": return "Power 启动键"
        default: return (Self.remoteKeys.first(where: { $0.id == id })?.title ?? id) + "键"
        }
    }

    static func currentBindingDescription(_ binding: XiaomiBinding?) -> String {
        guard let binding else { return "对应按键：未设置" }
        if let keycode = binding.keycode {
            let suffix: String
            switch keycode {
            case "ENC_CC": suffix = "逆时针旋钮"
            case "ENC_CW": suffix = "顺时针旋钮"
            case "ENC_CLK": suffix = "旋钮按压"
            default: suffix = "键位"
            }
            return "对应按键：Codex Micro \(keycode) \(suffix)"
        }
        if let target = Self.controlTargets.first(where: { $0.binding == binding }) {
            return "对应按键：Codex Micro \(target.id) \(target.title)"
        }
        return "对应按键：Codex Micro 摇杆"
    }

    private func bindingTitle(_ binding: XiaomiBinding?) -> String {
        Self.bindingLabel(binding)
    }

    static func bindingLabel(_ binding: XiaomiBinding?) -> String {
        guard let binding else { return "未绑定" }
        if let keycode = binding.keycode { return keycode }
        return (Self.controlTargets + Self.agentTargets + Self.actionTargets)
            .first(where: { $0.binding == binding })?.title ?? "摇杆"
    }

    private func save(session: BindingEditorSession) {
        guard session.hasChanges, !session.isVoiceLocked else { return }
        do {
            var updated = state.keyMapping
            updated.updateValue(session.binding, forKey: session.id)
            try state.saveKeyMapping(updated)
            editingSession = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreDefaults() {
        state.restoreDefaultKeyMapping()
    }
}
