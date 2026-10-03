import AppKit
import SwiftUI

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
        case "power", "voice": radius = 35
        case "ok": radius = 69
        default: radius = 49
        }
        let topButton = keyID == "power" || keyID == "voice"
        // At 50% image scale, move the top edge down 1 pt and keep the bottom edge.
        return Path(ellipseIn: CGRect(x: center.x - radius * scale,
                                      y: center.y - radius * scale + (topButton ? 2 * scale : 0),
                                      width: radius * 2 * scale,
                                      height: (radius * 2 - (topButton ? 2 : 0)) * scale))
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

struct KeyMappingPage: View {
    var state: AppState

    private struct BindingEditorSession: Identifiable {
        let id: String
        var binding: XiaomiBinding?
    }

    @State private var editingSession: BindingEditorSession?
    private var selectedKey: String { editingSession?.id ?? "" }
    private var editingBinding: XiaomiBinding? {
        get { editingSession?.binding }
        nonmutating set { editingSession?.binding = newValue }
    }
    @State private var errorMessage: String?
    @State private var showsRestoreConfirmation = false
    @State private var pendingTarget: BindingTarget?

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
            title: "Agent \(index)",
            detail: "AG0\(index)",
            symbol: "person.crop.square",
            binding: .init(kind: .key, keycode: "AG0\(index)", agent: index, angle: nil)
        )
    }

    private static let actionTargets = [
        BindingTarget(id: "ACT06", title: "快速", detail: "ACT06", symbol: "bolt", binding: .init(kind: .key, keycode: "ACT06", agent: nil, angle: nil)),
        BindingTarget(id: "ACT07", title: "同意", detail: "ACT07", symbol: "checkmark.circle", binding: .init(kind: .key, keycode: "ACT07", agent: nil, angle: nil)),
        BindingTarget(id: "ACT08", title: "拒绝", detail: "ACT08", symbol: "xmark.circle", binding: .init(kind: .key, keycode: "ACT08", agent: nil, angle: nil)),
        BindingTarget(id: "ACT09", title: "分支", detail: "ACT09", symbol: "arrow.triangle.branch", binding: .init(kind: .key, keycode: "ACT09", agent: nil, angle: nil)),
        BindingTarget(id: "ACT10", title: "按住说话", detail: "ACT10", symbol: "mic", binding: .init(kind: .key, keycode: "ACT10", agent: nil, angle: nil)),
        BindingTarget(id: "ACT12", title: "提交", detail: "ACT12", symbol: "paperplane", binding: .init(kind: .key, keycode: "ACT12", agent: nil, angle: nil)),
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
            Text("键位映射").font(.largeTitle.weight(.semibold))
            Text("点击小米遥控器上的按键，在弹出的 Codex Micro 面板中查看或修改绑定。")
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
            bindingEditorSheet(for: session.id)
        }
        .confirmationDialog("恢复默认键位？", isPresented: $showsRestoreConfirmation) {
            Button("恢复默认", role: .destructive, action: restoreDefaults)
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有自定义绑定都会被默认映射替换。")
        }
        .alert("无法保存键位映射", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var remoteSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(state.remoteName ?? "小米遥控器 RC003").font(.title3.weight(.semibold))
                Label(
                    state.remoteConnected ? "已连接" : "未连接",
                    systemImage: state.remoteConnected ? "checkmark.circle.fill" : "circle.dashed"
                )
                .foregroundStyle(state.remoteConnected ? Color.green : Color.secondary)
                Text("\(boundCount) 个按键已绑定 · \(Self.remoteKeys.count - boundCount) 个未绑定")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("直接点击左侧遥控器上的按键查看当前绑定。保存后，新映射会立即生效；遥控器未连接时也可以离线配置。语音键固定为按住说话。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("恢复默认键位") { showsRestoreConfirmation = true }
                .buttonStyle(.bordered)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minHeight: 300, alignment: .topLeading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }

    private func bindingEditorSheet(for keyID: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(remoteKeyTitle(keyID)).font(.title3.weight(.semibold))
                HStack(spacing: 8) {
                    Text("当前绑定").foregroundStyle(.secondary)
                    Text(bindingTitle(binding(for: keyID))).fontWeight(.semibold)
                    if let detail = bindingDetail(binding(for: keyID)) {
                        Text(detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
            .padding(16)

            Divider()

            codexPanel
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            HStack {
                Button("取消") { editingSession = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存更改", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(editingBinding == binding(for: keyID))
            }
            .padding(16)
        }
        .frame(width: 320, height: isVoiceLocked ? 524 : 500)
        .confirmationDialog("这个键位已经被占用", isPresented: Binding(
            get: { pendingTarget != nil },
            set: { if !$0 { pendingTarget = nil } }
        )) {
            Button("仍然绑定") {
                editingBinding = pendingTarget?.binding
                pendingTarget = nil
            }
            Button("取消", role: .cancel) { pendingTarget = nil }
        } message: {
            if let pendingTarget {
                Text("\(pendingTarget.title) 已绑定到\(owners(of: pendingTarget.binding).joined(separator: "、"))。允许多个遥控器按键使用同一个目标。")
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

    private var codexPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Codex Micro").font(.headline)
            Text("旋钮、摇杆点击展开操作菜单。")
                .font(.caption).foregroundStyle(.secondary)

            if isVoiceLocked {
                Label("语音键固定为按住说话", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }

            microImagePanel
                .frame(maxWidth: .infinity, alignment: .center)

            Button {
                editingBinding = nil
            } label: {
                Label("取消绑定", systemImage: "nosign")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(currentBinding == nil ? Color.accentColor : Color.secondary)
            .disabled(isVoiceLocked)
        }
        .padding(12)
        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var microImagePanel: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 480
            ZStack(alignment: .topLeading) {
                microProductImage.resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fit)

                controlMenu("旋钮", targets: Array(Self.controlTargets.prefix(3)), joystick: false)
                    .frame(width: 94 * scale, height: 94 * scale)
                    .position(x: 73 * scale, y: 74 * scale)
                controlMenu("摇杆", targets: Array(Self.controlTargets.dropFirst(3)), joystick: true)
                    .frame(width: 94 * scale, height: 94 * scale)
                    .position(x: 407 * scale, y: 75 * scale)

                ForEach(Array(Self.agentTargets.enumerated()), id: \.element.id) { index, target in
                    let firstRow = index < 2
                    let column = firstRow ? index + 1 : index - 2
                    targetButton(target)
                        .frame(width: 102 * scale, height: 102 * scale)
                        .position(x: CGFloat(73 + column * 111) * scale,
                                  y: CGFloat(firstRow ? 74 : 185) * scale)
                }
                ForEach(Array(Self.actionTargets.prefix(4).enumerated()), id: \.element.id) { index, target in
                    targetButton(target)
                        .frame(width: 102 * scale, height: 102 * scale)
                        .position(x: CGFloat(73 + index * 111) * scale, y: 296 * scale)
                }
                targetButton(Self.actionTargets[4])
                    .frame(width: 212 * scale, height: 102 * scale)
                    .position(x: 239.5 * scale, y: 407 * scale)
                targetButton(Self.actionTargets[5])
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

    private func controlMenu(_ title: String, targets: [BindingTarget], joystick: Bool) -> some View {
        let selected = targets.contains { $0.binding == currentBinding }
        return Menu {
            ForEach(targets) { target in
                Button {
                    chooseTarget(target)
                } label: {
                    Label(target.title, systemImage: currentBinding == target.binding ? "checkmark" : target.symbol)
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
        .disabled(isVoiceLocked)
        .help(selected ? "\(title) · \(bindingTitle(currentBinding))" : "\(title) · 点击选择操作")
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "已选择：\(bindingTitle(currentBinding))" : "未选择")
    }

    private var remoteProductImage: Image {
        guard let url = Bundle.main.url(forResource: "XiaomiRemote", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return Image(systemName: "av.remote.fill")
        }
        return Image(nsImage: image)
    }

    private func remoteHotspot(_ keyID: String) -> some View {
        let configured = binding(for: keyID) != nil
        let outline = RemoteKeyOutlineShape(keyID: keyID)
        return Button {
            pendingTarget = nil
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
        .help("\(remoteKeyTitle(keyID)) · \(bindingTitle(binding(for: keyID)))")
        .accessibilityLabel("\(remoteKeyTitle(keyID))，\(bindingTitle(binding(for: keyID)))")
    }

    private func targetButton(_ target: BindingTarget) -> some View {
        let selected = currentBinding == target.binding
        return Button {
            chooseTarget(target)
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
        .disabled(isVoiceLocked)
        .help("\(target.title) · \(target.detail)\(owners(of: target.binding).isEmpty ? "" : " · 已绑定：" + owners(of: target.binding).joined(separator: "、"))")
        .accessibilityLabel(target.title)
        .accessibilityValue(selected ? "已选择" : "未选择")
    }

    private func chooseTarget(_ target: BindingTarget) {
        guard !isVoiceLocked else { return }
        if owners(of: target.binding).isEmpty || currentBinding == target.binding {
            editingBinding = target.binding
        } else {
            pendingTarget = target
        }
    }

    private var currentBinding: XiaomiBinding? { editingBinding }
    private var isVoiceLocked: Bool { selectedKey == "voice" }
    private var boundCount: Int { Self.remoteKeys.filter { binding(for: $0.id) != nil }.count }

    private func binding(for key: String) -> XiaomiBinding? {
        guard let stored = state.keyMapping[key] else { return nil }
        return stored
    }

    private func owners(of binding: XiaomiBinding) -> [String] {
        Self.remoteKeys.compactMap { key in
            guard key.id != selectedKey, self.binding(for: key.id) == binding else { return nil }
            return key.title
        }
    }

    private func remoteKeyTitle(_ id: String) -> String {
        Self.remoteKeys.first(where: { $0.id == id })?.title ?? id
    }

    private func bindingTitle(_ binding: XiaomiBinding?) -> String {
        guard let binding else { return "未绑定" }
        return (Self.controlTargets + Self.agentTargets + Self.actionTargets)
            .first(where: { $0.binding == binding })?.title ?? binding.keycode ?? "摇杆"
    }

    private func bindingDetail(_ binding: XiaomiBinding?) -> String? {
        guard let binding else { return nil }
        return (Self.controlTargets + Self.agentTargets + Self.actionTargets)
            .first(where: { $0.binding == binding })?.detail
    }

    private func save() {
        do {
            var updated = state.keyMapping
            updated.updateValue(editingBinding, forKey: selectedKey)
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
