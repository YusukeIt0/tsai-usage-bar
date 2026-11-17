import Foundation

/// Version comparison and release parsing for the update check.
public struct AppVersion: Comparable, Equatable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    /// Accepts "0.1.4" or "v0.1.4". Anything else (pre-release suffixes, "dev") is rejected.
    public init?(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") { s.removeFirst() }
        let comps = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(comps.count) else { return nil }
        var parts: [Int] = []
        for c in comps {
            guard !c.isEmpty, c.allSatisfy(\.isASCII), c.allSatisfy(\.isNumber), let n = Int(c) else { return nil }
            parts.append(n)
        }
        self.parts = parts
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        for i in 0..<n {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }

    public var description: String { parts.map(String.init).joined(separator: ".") }
}

public enum ReleaseInfo {
    public static let repository = "YusukeIt0/tsai-usage-bar"
    public static let latestAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    /// Reads the version of the latest published, non-draft, non-pre-release release.
    public static func latestVersion(fromJSON data: Data) -> AppVersion? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (obj["draft"] as? Bool) != true, (obj["prerelease"] as? Bool) != true,
              let tag = obj["tag_name"] as? String else { return nil }
        return AppVersion(tag)
    }

    /// True only when both versions are known and the latest is newer.
    public static func isUpdate(latest: AppVersion?, current: AppVersion?) -> Bool {
        guard let latest, let current else { return false }
        return latest > current
    }

    /// The installer pinned to the release tag, so an update runs the script that shipped with it.
    public static func installerURL(for version: AppVersion) -> URL {
        URL(string: "https://raw.githubusercontent.com/\(repository)/v\(version)/install.sh")!
    }
}
