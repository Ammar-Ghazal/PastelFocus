import Foundation

/// Where everything lives. All paths come from here so tests can point at a temp vault.
public struct VaultConfig: Sendable, Equatable {
    public var root: URL
    /// Vault-relative folder holding `YYYY-MM-DD.md` daily notes.
    public var dailyFolder: String
    /// Vault-relative folder for PastelFocus's own files.
    public var appFolder: String
    /// When false, raw logs live in `privateLogs` instead of the vault (Hermes sees summaries only).
    public var logsInVault: Bool
    public var privateLogs: URL

    public init(root: URL,
                dailyFolder: String = "Learning Library/Career/Daily Plans",
                appFolder: String = "PastelFocus",
                logsInVault: Bool = true,
                privateLogs: URL = VaultConfig.defaultSupportDirectory.appendingPathComponent("Logs")) {
        self.root = root
        self.dailyFolder = dailyFolder
        self.appFolder = appFolder
        self.logsInVault = logsInVault
        self.privateLogs = privateLogs
    }

    public static var defaultSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PastelFocus", isDirectory: true)
    }

    public var appDir: URL { root.appendingPathComponent(appFolder, isDirectory: true) }
    public var dailyDir: URL { root.appendingPathComponent(dailyFolder, isDirectory: true) }
    public var logsDir: URL { logsInVault ? appDir.appendingPathComponent("Logs", isDirectory: true) : privateLogs }
    public var statsDir: URL { appDir.appendingPathComponent("Stats", isDirectory: true) }
    public var gardenDir: URL { appDir.appendingPathComponent("Garden", isDirectory: true) }

    public var inbox: URL { appDir.appendingPathComponent("Inbox.md") }
    public var backlog: URL { appDir.appendingPathComponent("Backlog.md") }
    public var now: URL { appDir.appendingPathComponent("Now.md") }
    public var insights: URL { appDir.appendingPathComponent("Insights.md") }
    public var problems: URL { appDir.appendingPathComponent("Problems.md") }
    public var tags: URL { appDir.appendingPathComponent("Tags.md") }

    public func dailyNote(_ day: String) -> URL { dailyDir.appendingPathComponent("\(day).md") }

    public func relativePath(_ url: URL) -> String {
        let base = root.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        return p.hasPrefix(base + "/") ? String(p.dropFirst(base.count + 1)) : p
    }

    public func url(forRelative path: String) -> URL { root.appendingPathComponent(path) }

    /// Day encoded in a daily note's file name, if `relative` is a daily note.
    public func noteDay(forRelative relative: String) -> String? {
        guard relative.hasPrefix(dailyFolder + "/") else { return nil }
        let name = (relative as NSString).lastPathComponent
        guard name.hasSuffix(".md") else { return nil }
        let day = String(name.dropLast(3))
        return day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil ? day : nil
    }
}
