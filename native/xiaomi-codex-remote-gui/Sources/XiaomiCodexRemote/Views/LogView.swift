import SwiftUI

/// Scrollable log panel with auto-scroll, pause/resume, and source-based coloring.
struct LogView: View {
    let lines: [LogLine]
    @State private var autoScroll: Bool = true

    private func sourceColor(_ source: String) -> Color {
        switch source {
        case "bridge": return .blue
        case "button": return .green
        case "hid": return .cyan
        case "ble", "atvv": return .purple
        case "audio": return .orange
        case "chatgpt": return .pink
        case "app": return .secondary
        default: return .primary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("日志")
                    .font(.headline)
                Spacer()
                Button(autoScroll ? "⏸ 暂停" : "▶ 恢复") {
                    autoScroll.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(lines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text(Self.timeFormatter.string(from: line.timestamp))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 60, alignment: .leading)

                                Text(line.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(sourceColor(line.source))
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 1)
                            .id(line.id)
                        }
                    }
                }
                .onChange(of: lines.last?.id) { _, newID in
                    if autoScroll, let id = newID {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(.background)
    }
}
