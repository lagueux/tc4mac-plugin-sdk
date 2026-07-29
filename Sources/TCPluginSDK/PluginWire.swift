import Foundation

/// The host↔plugin wire (Plugin System §2). A plugin is a separate process:
/// requests and responses are length-prefixed JSON frames over its standard
/// input and output — the same shape the SFTP transport uses, and for the
/// same reasons. It is language-agnostic (the SDK promises Swift, C, and
/// Rust plugins), it needs no installation ceremony beyond dropping a
/// `.tcplugin` bundle in the folder, and a crashed plugin is a closed pipe
/// rather than a crashed app.
///
/// Each method's payload is its own `Codable` type, carried as raw JSON, so
/// adding a method or a field never changes this envelope.

/// Which `PluginError` a wire failure carries.
public enum PluginErrorKind: String, Codable, Sendable {
    case notFound, alreadyExists, permissionDenied, cancelled, notSupported, failed
}

public enum PluginWire {
    /// Frames bigger than this are refused: a corrupt or hostile length must
    /// not make the host allocate arbitrarily.
    public static let maxFrameLength = 64 * 1024 * 1024

    public struct Request: Codable, Sendable {
        public var id: Int
        public var method: String
        /// JSON payload for `method`, empty when it takes none.
        public var payload: Data

        public init(id: Int, method: String, payload: Data = Data()) {
            self.id = id
            self.method = method
            self.payload = payload
        }
    }

    public struct Response: Codable, Sendable {
        public var id: Int
        public var payload: Data?
        public var error: ErrorPayload?
        /// False for an intermediate chunk of a streamed reply (a directory
        /// batch, a slice of a file); the host keeps reading until true.
        public var isFinal: Bool

        public init(
            id: Int, payload: Data? = nil, error: ErrorPayload? = nil, isFinal: Bool = true
        ) {
            self.id = id
            self.payload = payload
            self.error = error
            self.isFinal = isFinal
        }
    }

    /// `PluginError` on the wire.
    public struct ErrorPayload: Codable, Sendable, Equatable {
        public var kind: PluginErrorKind
        public var detail: String

        public init(kind: PluginErrorKind, detail: String) {
            self.kind = kind
            self.detail = detail
        }

        public init(_ error: PluginError) {
            switch error {
            case .notFound(let what): self = .init(kind: .notFound, detail: what)
            case .alreadyExists(let what): self = .init(kind: .alreadyExists, detail: what)
            case .permissionDenied(let what): self = .init(kind: .permissionDenied, detail: what)
            case .cancelled: self = .init(kind: .cancelled, detail: "")
            case .notSupported(let what): self = .init(kind: .notSupported, detail: what)
            case .failed(let what): self = .init(kind: .failed, detail: what)
            }
        }

        public var error: PluginError {
            switch kind {
            case .notFound: return .notFound(detail)
            case .alreadyExists: return .alreadyExists(detail)
            case .permissionDenied: return .permissionDenied(detail)
            case .cancelled: return .cancelled
            case .notSupported: return .notSupported(detail)
            case .failed: return .failed(detail)
            }
        }
    }

    /// The methods a plugin may implement. A plugin answers `notSupported`
    /// for anything outside what its manifest declares.
    public enum Method {
        /// Handshake: the host sends its version, the plugin replies with
        /// what it is. Always first, so a mismatch is caught before any work.
        public static let hello = "hello"
        // File-system plugin
        public static let list = "fs.list"
        public static let stat = "fs.stat"
        public static let read = "fs.read"
        public static let write = "fs.write"
        public static let makeDirectory = "fs.mkdir"
        public static let delete = "fs.delete"
        public static let rename = "fs.rename"
        public static let probe = "fs.probe"
        public static let execute = "fs.execute"
        // Packer plugin
        public static let archiveEntries = "archive.entries"
        public static let archiveExtract = "archive.extract"
        public static let archivePack = "archive.pack"
    }

    /// The plugin's answer to `hello`.
    public struct Hello: Codable, Sendable, Equatable {
        public var id: String
        public var displayName: String
        public var sdkVersion: Int
        /// Raw value of `FileSystemPluginCapabilities`, when it serves a
        /// file system.
        public var fileSystemCapabilities: Int?
        /// Raw value of `PackerCapabilities`, when it serves an archive
        /// format, with the extensions it claims.
        public var packerCapabilities: Int?
        public var packerExtensions: [String]?

        public init(
            id: String, displayName: String, sdkVersion: Int = PluginWire.sdkVersion,
            fileSystemCapabilities: Int? = nil,
            packerCapabilities: Int? = nil, packerExtensions: [String]? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.sdkVersion = sdkVersion
            self.fileSystemCapabilities = fileSystemCapabilities
            self.packerCapabilities = packerCapabilities
            self.packerExtensions = packerExtensions
        }
    }

    /// Bumped when the envelope or a payload changes incompatibly. The host
    /// refuses a plugin built against a newer one rather than guessing.
    public static let sdkVersion = 1

    // MARK: - Framing

    /// One frame: a 4-byte big-endian length, then the JSON.
    public static func frame(_ payload: Data) -> Data {
        var framed = Data(capacity: payload.count + 4)
        let length = UInt32(payload.count)
        framed.append(UInt8(truncatingIfNeeded: length >> 24))
        framed.append(UInt8(truncatingIfNeeded: length >> 16))
        framed.append(UInt8(truncatingIfNeeded: length >> 8))
        framed.append(UInt8(truncatingIfNeeded: length))
        framed.append(payload)
        return framed
    }

    /// The frame length from a 4-byte header, refusing an implausible one.
    public static func frameLength(_ header: Data) throws -> Int {
        guard header.count == 4 else {
            throw PluginError.failed("short frame header") // l10n:exempt: diagnostic
        }
        let length = header.reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, length <= maxFrameLength else {
            throw PluginError.failed("frame length out of range: \(length)") // l10n:exempt: diagnostic
        }
        return length
    }
}

// MARK: - Payloads

/// Payloads are small and explicit so both sides stay readable. File bytes
/// travel base64 inside JSON, which is the one place this wire is wasteful;
/// bulk transfers move to a file handle when the packer type lands.
public enum PluginPayload {
    public struct Path: Codable, Sendable {
        public var path: String
        public init(path: String) { self.path = path }
    }

    public struct Entry: Codable, Sendable, Equatable {
        public var name: String
        public var isDirectory: Bool
        public var size: Int64?
        public var modified: Date?
        public var posixPermissions: UInt16?

        public init(
            name: String, isDirectory: Bool, size: Int64? = nil,
            modified: Date? = nil, posixPermissions: UInt16? = nil
        ) {
            self.name = name
            self.isDirectory = isDirectory
            self.size = size
            self.modified = modified
            self.posixPermissions = posixPermissions
        }
    }

    public struct Entries: Codable, Sendable {
        public var entries: [Entry]
        public init(entries: [Entry]) { self.entries = entries }
    }

    public struct Chunk: Codable, Sendable {
        public var data: Data
        public init(data: Data) { self.data = data }
    }

    public struct Write: Codable, Sendable {
        public var path: String
        public var data: Data
        public var resumeAt: UInt64?

        public init(path: String, data: Data, resumeAt: UInt64? = nil) {
            self.path = path
            self.data = data
            self.resumeAt = resumeAt
        }
    }

    public struct Delete: Codable, Sendable {
        public var path: String
        public var isDirectory: Bool
        public init(path: String, isDirectory: Bool) {
            self.path = path
            self.isDirectory = isDirectory
        }
    }

    public struct Rename: Codable, Sendable {
        public var path: String
        public var newPath: String
        public var copy: Bool
        public init(path: String, newPath: String, copy: Bool) {
            self.path = path
            self.newPath = newPath
            self.copy = copy
        }
    }

    /// One archive entry on the wire — `ArchiveEntryHeader` without the
    /// types JSON cannot carry directly.
    public struct ArchiveEntry: Codable, Sendable, Equatable {
        public var path: String
        public var isDirectory: Bool
        public var size: Int64?
        public var packedSize: Int64?
        public var modified: Date?
        public var isEncrypted: Bool
        public var method: String?

        public init(
            path: String, isDirectory: Bool = false, size: Int64? = nil,
            packedSize: Int64? = nil, modified: Date? = nil,
            isEncrypted: Bool = false, method: String? = nil
        ) {
            self.path = path
            self.isDirectory = isDirectory
            self.size = size
            self.packedSize = packedSize
            self.modified = modified
            self.isEncrypted = isEncrypted
            self.method = method
        }
    }

    public struct ArchiveEntries: Codable, Sendable {
        public var entries: [ArchiveEntry]
        public init(entries: [ArchiveEntry]) { self.entries = entries }
    }

    /// Which archive, and where the extracted file should land.
    public struct Extract: Codable, Sendable {
        public var archive: String
        public var entry: String
        public var destination: String

        public init(archive: String, entry: String, destination: String) {
            self.archive = archive
            self.entry = entry
            self.destination = destination
        }
    }

    /// Files to add, with the names they take inside the archive.
    public struct Pack: Codable, Sendable {
        public struct Input: Codable, Sendable {
            public var source: String
            public var pathInArchive: String
            public init(source: String, pathInArchive: String) {
                self.source = source
                self.pathInArchive = pathInArchive
            }
        }

        public var archive: String
        public var files: [Input]
        public var savePaths: Bool
        public var compressionLevel: Int?

        public init(
            archive: String, files: [Input], savePaths: Bool = true,
            compressionLevel: Int? = nil
        ) {
            self.archive = archive
            self.files = files
            self.savePaths = savePaths
            self.compressionLevel = compressionLevel
        }
    }

    public struct DestinationState: Codable, Sendable, Equatable {
        public var state: String  // absent | exists | resumable | unknown
        public var offset: UInt64?
        public init(state: String, offset: UInt64? = nil) {
            self.state = state
            self.offset = offset
        }
    }
}
