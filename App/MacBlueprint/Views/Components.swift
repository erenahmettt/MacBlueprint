import AppKit
import BlueprintCore
import SwiftUI
import UniformTypeIdentifiers

extension AppItem: @retroactive Identifiable {
    public var id: String { path }
}

/// A small number with a caption, used in the overview header.
struct StatTile: View {
    let title: String
    let value: String
    var detail: String?
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Where an app came from, as a small colored capsule.
struct SourceBadge: View {
    let source: AppItem.Source

    var body: some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var title: String {
        switch source {
        case .appStore: "App Store"
        case .homebrew: "Homebrew"
        case .system: "Built-in"
        case .manual: "Installed by hand"
        }
    }

    private var color: Color {
        switch source {
        case .appStore: .blue
        case .homebrew: .orange
        case .system: .gray
        case .manual: .secondary
        }
    }
}

/// The app's real icon when it is installed here, a placeholder otherwise.
struct AppIcon: View {
    let path: String
    var size: CGFloat = 18

    var body: some View {
        Group {
            if FileManager.default.fileExists(atPath: path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
            } else {
                // Not on this Mac: the generic app icon, dimmed.
                Image(nsImage: NSWorkspace.shared.icon(for: .application))
                    .resizable()
                    .opacity(0.6)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A shell command with a copy button.
struct CommandRow: View {
    let command: String

    var body: some View {
        HStack {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

enum Panels {
    /// Asks where to save a file. Returns nil when cancelled.
    @MainActor
    static func save(suggestedName: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Asks for a folder. Returns nil when cancelled.
    @MainActor
    static func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}
