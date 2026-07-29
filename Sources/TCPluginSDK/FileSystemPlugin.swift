import Foundation

/// A file-system plugin (Plugin System §3.2 — the WFX equivalent): a new
/// scheme in the drive bar that behaves like a directory tree. It is
/// deliberately the same handful of primitives as `RemoteTransport`: the host
/// implements the whole VFS against these, so copy, move, resume, queueing,
/// undo, search, and the Transfer Manager all come from the one tested
/// engine — the "write it once against the VFS" rule.
///
/// Where WFX has FsFindFirst/FsFindNext/FsFindClose with an opaque handle and
/// several searches open at once, this has one streaming `list`: Swift's
/// async sequence carries the same state with none of the handle bookkeeping.
public protocol FileSystemPlugin: Sendable {
    /// What this plugin can do, so the host enables only what works
    /// (TC caches the equivalent WFX/WCX capability bits at install time).
    var capabilities: FileSystemPluginCapabilities { get }

    /// Opens a session. The plugin keeps whatever connection it needs; the
    /// host calls `disconnect` when the user leaves or quits. `services` is
    /// how the plugin reports progress, logs, prompts, and reads passwords.
    func connect(services: any PluginHostServices) async throws

    /// TC's FsDisconnect. Only offered in the UI when `.session` is declared:
    /// TC's rule is that a connectionless plugin must not advertise a
    /// Disconnect it cannot honour.
    func disconnect() async

    /// Streams a directory in batches, like every other VFS backend.
    func list(_ path: String) -> AsyncThrowingStream<[PluginPayload.Entry], Error>
    func stat(_ path: String) async throws -> PluginPayload.Entry

    func read(_ path: String) -> AsyncThrowingStream<Data, Error>
    /// Writes a whole file. Resumable plugins receive `resumeAt` — the byte
    /// offset already present at the destination.
    func write(_ path: String, data: Data, resumeAt: UInt64?) async throws

    func makeDirectory(_ path: String) async throws
    func delete(_ path: String, isDirectory: Bool) async throws
    /// Rename or move **within** this plugin's namespace — WFX's
    /// FsRenMovFile, which is why remote-to-remote copying never round-trips
    /// through a local file.
    func rename(_ path: String, to newPath: String, copy: Bool) async throws

    /// What already exists at `path`, asked BEFORE any bytes move. This is
    /// WFX's two-call protocol (FsGetFile/FsPutFile called once with no
    /// OVERWRITE flag, answering FS_FILE_EXISTS or
    /// FS_FILE_EXISTSRESUMEALLOWED) made explicit, so the collision dialog
    /// can offer Resume truthfully instead of guessing.
    func probe(_ path: String) async throws -> PluginDestinationState

    /// FsExecuteFile: what happens when the user opens a row. Lets a plugin
    /// root offer its own actions ("Add connection…"), redirect the panel
    /// elsewhere, or ask the host to download and open the file.
    func execute(_ verb: PluginExecVerb, on path: String) async throws -> PluginExecResult

    /// FsStatusInfo: the host brackets each operation so a plugin can pool
    /// connections or flush caches. Optional — the default ignores it.
    func operationWillBegin(_ operation: PluginOperation, at path: String) async
    func operationDidEnd(_ operation: PluginOperation, at path: String) async
}

public extension FileSystemPlugin {
    func disconnect() async {}
    func operationWillBegin(_ operation: PluginOperation, at path: String) async {}
    func operationDidEnd(_ operation: PluginOperation, at path: String) async {}
    func probe(_ path: String) async throws -> PluginDestinationState {
        // Without a cheap existence check the honest answer is "ask the
        // engine to find out", which is what .unknown means.
        .unknown
    }
    func execute(_ verb: PluginExecVerb, on path: String) async throws -> PluginExecResult {
        .notHandled
    }
}

/// The WFX/WCX capability bits, natively. Declared once and honoured by the
/// UI: an action the plugin cannot do is disabled rather than offered and
/// then failed.
public struct FileSystemPluginCapabilities: OptionSet, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let write = FileSystemPluginCapabilities(rawValue: 1 << 0)
    public static let delete = FileSystemPluginCapabilities(rawValue: 1 << 1)
    public static let makeDirectory = FileSystemPluginCapabilities(rawValue: 1 << 2)
    public static let rename = FileSystemPluginCapabilities(rawValue: 1 << 3)
    /// Uploads can continue from an offset (FS_FILE_EXISTSRESUMEALLOWED).
    public static let resume = FileSystemPluginCapabilities(rawValue: 1 << 4)
    /// Has a connection worth disconnecting — gates the Disconnect command.
    public static let session = FileSystemPluginCapabilities(rawValue: 1 << 5)
    /// Wants its own connection per parallel transfer (TC's BG_ASK_USER):
    /// the Transfer Manager asks before fanning out.
    public static let ownConnectionPerTransfer =
        FileSystemPluginCapabilities(rawValue: 1 << 6)
    /// Rows are really local files (FsLinksToLocalFiles) — the panel may
    /// hand their paths straight to other tools.
    public static let backedByLocalFiles = FileSystemPluginCapabilities(rawValue: 1 << 7)
}

/// What `probe` found at a destination.
public enum PluginDestinationState: Sendable, Equatable {
    case absent
    case exists
    /// Exists and an interrupted upload can continue from `offset`.
    case existsResumable(offset: UInt64)
    /// The plugin cannot say cheaply; the engine falls back to its own check.
    case unknown
}

/// FsExecuteFile's verbs.
public enum PluginExecVerb: Sendable, Equatable {
    case open
    case properties
    /// TC passes "chmod xxx"; POSIX mode here, since that is what macOS has.
    case setPosixMode(UInt16)
    /// TC's "quote <commandline>" — a command typed in the command line.
    case command(String)
}

/// What the host should do after `execute`.
public enum PluginExecResult: Sendable, Equatable {
    /// The plugin did it; nothing further.
    case handled
    /// Not ours — the host applies its normal behaviour.
    case notHandled
    /// Show this path instead (FS_EXEC_SYMLINK: how plugins implement
    /// "cd elsewhere" and shortcut rows).
    case redirect(String)
    /// Copy it to a temporary file and open that (FS_EXEC_YOURSELF).
    case downloadAndOpen
}

/// The FS_STATUS_OP_* set, trimmed to the operations tc4mac actually runs.
public enum PluginOperation: String, Sendable, Codable, Equatable {
    case list
    case get
    case put
    case rename
    case delete
    case makeDirectory
    case calculateSize
    case search
    case synchronize
}
