import Foundation

/// Runs every scanner in parallel and assembles a ``Snapshot``.
public struct SnapshotBuilder: Sendable {
    public var context: ScanContext
    public var label: String?
    public var machine: MachineInfo
    public var now: @Sendable () -> Date

    public init(
        context: ScanContext = .live(),
        label: String? = nil,
        machine: MachineInfo = .current(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.context = context
        self.label = label
        self.machine = machine
        self.now = now
    }

    public func build() async -> Snapshot {
        async let apps = AppScanner().scan(context)
        async let homebrew = BrewScanner().scan(context)
        async let editors = EditorScanner().scan(context)
        async let devEnvironment = DevToolScanner().scan(context)
        async let shell = ShellScanner().scan(context)

        let brew = await homebrew
        let linkedApps = Self.link(await apps, to: brew.casks)

        return Snapshot(
            createdAt: now(),
            label: label,
            machine: machine,
            apps: linkedApps,
            homebrew: brew,
            editors: await editors,
            devEnvironment: await devEnvironment,
            shell: await shell,
            warnings: context.warnings.all
        )
    }

    /// Marks apps installed by a Homebrew cask, matching on the `.app` name.
    static func link(_ apps: [AppItem], to casks: [BrewCask]) -> [AppItem] {
        var caskByApp: [String: String] = [:]
        for cask in casks {
            for app in cask.apps {
                caskByApp[app.lowercased()] = cask.token
            }
        }
        return apps.map { app in
            let bundleName = ((app.path as NSString).lastPathComponent).lowercased()
            guard app.source != .appStore, let token = caskByApp[bundleName] else { return app }
            var linked = app
            linked.source = .homebrew
            linked.caskToken = token
            return linked
        }
    }
}

extension MachineInfo {
    /// Describes the Mac this process runs on. Reports the real hardware
    /// architecture even when running under Rosetta.
    public static func current() -> MachineInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let arm64 = sysctlInt("hw.optional.arm64") == 1
        return MachineInfo(
            model: sysctlString("hw.model"),
            architecture: arm64 ? "arm64" : "x86_64",
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func sysctlInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
