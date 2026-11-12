import Foundation

/// One automated step of a ``RestorePlan`` that a user can switch on or off.
public struct RestoreItem: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case tap
        case formula
        case cask
        case appStore
        case editorExtension(EditorKind)
    }

    /// Stable within a plan, e.g. `cask:spotify` or `extension:vscode:ms-python.python`.
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String?
    /// Selected unless the item deserves a look first (a cask matched on the app name only).
    public var selectedByDefault: Bool
}

extension RestorePlan {
    /// Every automated step, in the order restore.sh runs them.
    public var items: [RestoreItem] {
        var items: [RestoreItem] = []
        items += taps.map { RestoreItem(id: "tap:\($0)", kind: .tap, title: $0, detail: nil, selectedByDefault: true) }
        items += formulae
            .filter { !(addedMas && $0 == "mas") } // follows the App Store apps automatically
            .map { RestoreItem(id: "formula:\($0)", kind: .formula, title: $0, detail: nil, selectedByDefault: true) }
        items += casks.map {
            RestoreItem(id: "cask:\($0.token)", kind: .cask, title: $0.token, detail: $0.note, selectedByDefault: !$0.needsReview)
        }
        items += appStoreApps.map {
            RestoreItem(id: "mas:\($0.id)", kind: .appStore, title: $0.name, detail: "App Store id \($0.id)", selectedByDefault: true)
        }
        for inventory in extensions {
            items += inventory.extensions.map {
                RestoreItem(
                    id: "extension:\(inventory.editor.rawValue):\($0.id)",
                    kind: .editorExtension(inventory.editor),
                    title: $0.id,
                    detail: nil,
                    selectedByDefault: true
                )
            }
        }
        return items
    }

    public var defaultSelection: Set<String> {
        Set(items.filter(\.selectedByDefault).map(\.id))
    }

    /// The same plan with only the selected automated steps. Manual steps and
    /// warnings are kept as they are.
    public func selecting(_ selection: Set<String>) -> RestorePlan {
        var plan = self
        plan.taps = taps.filter { selection.contains("tap:\($0)") }
        plan.casks = casks.filter { selection.contains("cask:\($0.token)") }
        plan.appStoreApps = appStoreApps.filter { selection.contains("mas:\($0.id)") }
        plan.formulae = formulae.filter { formula in
            if addedMas && formula == "mas" { return !plan.appStoreApps.isEmpty }
            return selection.contains("formula:\(formula)")
        }
        plan.extensions = extensions.compactMap { inventory in
            let kept = inventory.extensions.filter { selection.contains("extension:\(inventory.editor.rawValue):\($0.id)") }
            return kept.isEmpty ? nil : EditorInventory(editor: inventory.editor, extensions: kept)
        }
        return plan
    }
}
