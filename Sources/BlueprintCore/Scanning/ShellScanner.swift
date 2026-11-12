import Foundation

/// Detects the login shell, shell frameworks and prompt.
///
/// Only checks whether files or folders *exist*; dotfile contents are never read.
public struct ShellScanner: Scanner {
    public let id = "shell"

    static let frameworks: [(path: String, name: String)] = [
        (".oh-my-zsh", "oh-my-zsh"),
        (".zprezto", "prezto"),
        (".antidote", "antidote"),
        (".local/share/zinit", "zinit"),
        (".oh-my-bash", "oh-my-bash"),
        (".local/share/omf", "oh-my-fish"),
    ]

    public init() {}

    public func scan(_ context: ScanContext) async -> ShellInfo {
        let frameworks = Self.frameworks
            .filter { context.fs.isDirectory(context.fs.homePath($0.path)) }
            .map(\.name)

        let prompt: String?
        if context.runner.locate("starship") != nil {
            prompt = "starship"
        } else if context.runner.locate("oh-my-posh") != nil {
            prompt = "oh-my-posh"
        } else if context.fs.exists(context.fs.homePath(".p10k.zsh")) {
            prompt = "powerlevel10k"
        } else {
            prompt = nil
        }

        return ShellInfo(loginShell: context.environment["SHELL"], frameworks: frameworks, prompt: prompt)
    }
}
