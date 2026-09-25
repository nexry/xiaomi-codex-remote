import SwiftUI

/// Reusable status card showing an icon, title, status indicator, detail lines, and optional action button.
struct StatusCard: View {
    let icon: String
    let title: String
    let status: Status
    let details: [String]
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    enum Status {
        case good(String)
        case warning(String)
        case error(String)
        case inactive(String)

        var color: Color {
            switch self {
            case .good: return .green
            case .warning: return .orange
            case .error: return .red
            case .inactive: return .secondary
            }
        }

        var label: String {
            switch self {
            case .good(let s), .warning(let s), .error(let s), .inactive(let s): return s
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(status.color)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            ForEach(details, id: \.self) { detail in
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(status.label)
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                if let label = actionLabel, let action = action {
                    Button(label, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
