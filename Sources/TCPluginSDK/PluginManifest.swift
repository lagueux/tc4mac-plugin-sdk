import Foundation

/// The four plugin categories (Plugin System §1) — native equivalents of TC's
/// WCX/WFX/WLX/WDX. One bundle may implement several (combined plugins).
public enum PluginType: String, Codable, Sendable, CaseIterable {
    case packer      // WCX: new archive formats
    case filesystem  // WFX: new VFS schemes
    case viewer      // WLX: new Lister content types
    case content     // WDX: custom columns / fields
}

/// manifest.json inside a .tcplugin bundle (Plugin System §2): what the plugin
/// is and what it declares, read before any code runs.
public struct PluginManifest: Codable, Equatable, Sendable {
    /// Reverse-DNS identifier, unique per plugin ("com.example.sevenzip").
    public var id: String
    public var displayName: String
    /// Plugin's own version, "major.minor.patch".
    public var version: String
    /// Oldest tc4mac that can host it, "major.minor.patch".
    public var minHostVersion: String
    public var types: [PluginType]
    /// Packer: archive extensions served ("7z", "rar").
    public var extensions: [String]
    /// FileSystem: scheme names served ("gdrive").
    public var schemes: [String]
    /// Content: field ids provided ("bitrate", "exif.date").
    public var fields: [String]

    public init(
        id: String,
        displayName: String,
        version: String,
        minHostVersion: String = "0.1.0",
        types: [PluginType],
        extensions: [String] = [],
        schemes: [String] = [],
        fields: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.minHostVersion = minHostVersion
        self.types = types
        self.extensions = extensions
        self.schemes = schemes
        self.fields = fields
    }

    /// Optional arrays decode as empty so lean manifests stay lean.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        version = try container.decode(String.self, forKey: .version)
        minHostVersion = try container.decodeIfPresent(String.self, forKey: .minHostVersion)
            ?? "0.1.0"
        types = try container.decode([PluginType].self, forKey: .types)
        extensions = try container.decodeIfPresent([String].self, forKey: .extensions) ?? []
        schemes = try container.decodeIfPresent([String].self, forKey: .schemes) ?? []
        fields = try container.decodeIfPresent([String].self, forKey: .fields) ?? []
    }
}

/// "1.2.3"-style version triple; anything missing parses as zero, extra
/// components are ignored. Enough for min-host gating — not full semver.
public struct HostVersion: Comparable, Sendable, Equatable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init(_ text: String) {
        let parts = text.split(separator: ".").map { Int($0) ?? 0 }
        major = parts.count > 0 ? parts[0] : 0
        minor = parts.count > 1 ? parts[1] : 0
        patch = parts.count > 2 ? parts[2] : 0
    }

    public static func < (lhs: HostVersion, rhs: HostVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
