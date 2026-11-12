import Testing
@testable import BlueprintCore

@Suite struct EditorScannerTests {
    @Test func readsExtensionsManifest() async throws {
        let tree = try FixtureTree()
        try tree.write("/Users/tester/.vscode/extensions/extensions.json", """
        [
          { "identifier": { "id": "ms-vscode.cpptools", "uuid": "x" }, "version": "1.32.2" },
          { "identifier": { "id": "Swiftlang.Swift-VSCode" }, "version": "2.16.6" }
        ]
        """)

        let editors = await EditorScanner().scan(tree.context())

        #expect(editors.map(\.editor) == [.vscode])
        #expect(editors[0].extensions == [
            EditorExtension(id: "ms-vscode.cpptools", version: "1.32.2"),
            EditorExtension(id: "swiftlang.swift-vscode", version: "2.16.6"),
        ])
    }

    @Test func fallsBackToFolderNamesAndKeepsNewestVersion() async throws {
        let tree = try FixtureTree()
        try tree.mkdir("/Users/tester/.antigravity/extensions/n2ns.antigravity-panel-2.6.1-universal")
        try tree.mkdir("/Users/tester/.antigravity/extensions/n2ns.antigravity-panel-2.6.10-universal")
        try tree.mkdir("/Users/tester/.antigravity/extensions/llvm-vs-code-extensions.lldb-dap-0.4.1-universal")
        try tree.mkdir("/Users/tester/.antigravity/extensions/not-an-extension")

        let editors = await EditorScanner().scan(tree.context())

        #expect(editors.map(\.editor) == [.antigravity])
        #expect(editors[0].extensions == [
            EditorExtension(id: "llvm-vs-code-extensions.lldb-dap", version: "0.4.1"),
            EditorExtension(id: "n2ns.antigravity-panel", version: "2.6.10"),
        ])
    }

    @Test func skipsEditorsThatAreNotInstalled() async throws {
        let tree = try FixtureTree()
        #expect(await EditorScanner().scan(tree.context()).isEmpty)
    }
}
