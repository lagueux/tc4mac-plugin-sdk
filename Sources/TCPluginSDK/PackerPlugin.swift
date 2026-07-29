import Foundation

/// A packer plugin (Plugin System §3.1 — the WCX equivalent): a new archive
/// format the panel can enter, extract from, and where the format allows,
/// write to.
///
/// WCX exposes an archive as a cursor: ReadHeader yields the next entry and
/// ProcessFile must be called for *every* entry, even unwanted ones, because
/// it is what advances the stream. That wart exists to serve one real
/// constraint — a solid archive is a single forward-only decode, so reaching
/// entry *n* means decoding everything before it. This protocol keeps the
/// constraint and drops the wart: `entries` is an async sequence, and
/// `extract` states plainly which entry is wanted.
public protocol PackerPlugin: Sendable {
    /// What the format supports. TC caches the equivalent bits at install
    /// time and greys out the rest of its UI; tc4mac gates the Pack and
    /// Unpack dialogs from these, so an action is offered only if it works.
    var capabilities: PackerCapabilities { get }

    /// Extensions served ("mht", "chm"). Matching is case-insensitive and
    /// without the dot.
    var extensions: [String] { get }

    /// Content-based detection (WCX's `CanYouHandleThisFile`, gated by
    /// `.detectByContent`): asked only when the extension does not match,
    /// which is how self-extracting archives get recognised.
    func canHandle(fileAt url: URL) async -> Bool

    /// Lists the archive in storage order. Order matters: for a solid
    /// archive it is also the decode order, and the host extracts in it.
    func entries(in archive: URL) -> AsyncThrowingStream<ArchiveEntryHeader, Error>

    /// Extracts one entry to `destination`. `services` carries progress —
    /// and, through its return value, the only cancellation path there is.
    func extract(
        _ entry: ArchiveEntryHeader, from archive: URL, to destination: URL,
        services: any PluginHostServices
    ) async throws

    /// Adds files to (or creates) an archive. Only called when `.create` or
    /// `.modify` is declared; without `.multipleFiles` the host calls it once
    /// per file, as TC does.
    func pack(
        _ files: [PackerInputFile], into archive: URL, options: PackerOptions,
        services: any PluginHostServices
    ) async throws

    /// Removes entries. Only called when `.delete` is declared.
    func delete(
        _ entries: [String], from archive: URL, services: any PluginHostServices
    ) async throws

    /// The next volume of a multi-part set (WCX's ChangeVolProc), asked when
    /// the current one ends mid-entry. Nil means the user could not supply
    /// it, which aborts the extraction rather than silently truncating.
    func nextVolume(after archive: URL) async -> URL?
}

public extension PackerPlugin {
    func canHandle(fileAt url: URL) async -> Bool { false }

    func pack(
        _ files: [PackerInputFile], into archive: URL, options: PackerOptions,
        services: any PluginHostServices
    ) async throws {
        throw PluginError.notSupported("This format cannot be written.") // l10n:exempt: boundary key
    }

    func delete(
        _ entries: [String], from archive: URL, services: any PluginHostServices
    ) async throws {
        throw PluginError.notSupported("Entries cannot be removed from this format.") // l10n:exempt: boundary key
    }

    func nextVolume(after archive: URL) async -> URL? { nil }
}

/// WCX's PK_CAPS_* bits, natively. Declared once; the UI reads them rather
/// than discovering limits by failing.
public struct PackerCapabilities: OptionSet, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Can create a new archive (PK_CAPS_NEW).
    public static let create = PackerCapabilities(rawValue: 1 << 0)
    /// Can add to an existing one (PK_CAPS_MODIFY).
    public static let modify = PackerCapabilities(rawValue: 1 << 1)
    /// Can remove entries (PK_CAPS_DELETE).
    public static let delete = PackerCapabilities(rawValue: 1 << 2)
    /// Accepts several files in one call (PK_CAPS_MULTIPLE). Without it the
    /// host packs one file per call.
    public static let multipleFiles = PackerCapabilities(rawValue: 1 << 3)
    /// Has settings worth a Configure button (PK_CAPS_OPTIONS).
    public static let options = PackerCapabilities(rawValue: 1 << 4)
    /// Recognises its files by content, not just extension (PK_CAPS_BY_CONTENT).
    public static let detectByContent = PackerCapabilities(rawValue: 1 << 5)
    /// Find Files may search inside these archives (PK_CAPS_SEARCHTEXT).
    public static let searchable = PackerCapabilities(rawValue: 1 << 6)
    /// Supports passwords (PK_CAPS_ENCRYPT).
    public static let encrypt = PackerCapabilities(rawValue: 1 << 7)
    /// One continuous decode: random access costs a rescan, so the host
    /// extracts a whole selection in one pass instead of seeking per file.
    public static let solid = PackerCapabilities(rawValue: 1 << 8)
    /// Split across volumes; `nextVolume(after:)` will be called.
    public static let multiVolume = PackerCapabilities(rawValue: 1 << 9)
}

/// One entry as the archive describes it (WCX's tHeaderDataEx, minus the
/// 32-bit size split and the DOS attribute bits).
public struct ArchiveEntryHeader: Sendable, Equatable {
    /// Path inside the archive, slash-separated, no leading slash.
    public var path: String
    public var isDirectory: Bool
    /// Uncompressed size; nil when the format does not say until extraction.
    public var size: Int64?
    public var packedSize: Int64?
    public var modified: Date?
    public var posixPermissions: UInt16?
    public var isEncrypted: Bool
    /// Free-form format detail shown in the panel ("Deflate", "LZX:21").
    public var method: String?

    public init(
        path: String,
        isDirectory: Bool = false,
        size: Int64? = nil,
        packedSize: Int64? = nil,
        modified: Date? = nil,
        posixPermissions: UInt16? = nil,
        isEncrypted: Bool = false,
        method: String? = nil
    ) {
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.packedSize = packedSize
        self.modified = modified
        self.posixPermissions = posixPermissions
        self.isEncrypted = isEncrypted
        self.method = method
    }
}

/// A file being packed, with the name it should take inside the archive —
/// which is not derivable from the source path once "keep paths" and
/// "leave out base directory" are in play.
public struct PackerInputFile: Sendable, Equatable {
    public var source: URL
    public var pathInArchive: String

    public init(source: URL, pathInArchive: String) {
        self.source = source
        self.pathInArchive = pathInArchive
    }
}

/// What the Pack dialog asked for.
public struct PackerOptions: Sendable, Equatable {
    /// Delete the sources once the archive is written (PK_PACK_MOVE_FILES).
    public var moveFiles: Bool
    /// Store directory names, rather than flattening (PK_PACK_SAVE_PATHS).
    public var savePaths: Bool
    /// Nil unless the user asked for encryption; the plugin gets the secret
    /// through `PluginHostServices.secret`, never as stored text.
    public var encrypt: Bool
    /// 0…9 where the format has levels; nil means "the format's default".
    public var compressionLevel: Int?

    public init(
        moveFiles: Bool = false, savePaths: Bool = true,
        encrypt: Bool = false, compressionLevel: Int? = nil
    ) {
        self.moveFiles = moveFiles
        self.savePaths = savePaths
        self.encrypt = encrypt
        self.compressionLevel = compressionLevel
    }
}
