import Foundation

/// What a plugin may ask the host to do on its behalf (Plugin System §3):
/// TC hands a WFX plugin three function pointers at `FsInit` — ProgressProc,
/// LogProc, RequestProc — plus a CryptProc for stored passwords, and a WCX
/// plugin gets the same progress/cancel contract through ProcessDataProc.
/// This is the one native equivalent, shared by every plugin type.
///
/// Two rules follow TC's design deliberately:
/// - **Cancellation only exists where progress is reported.** `report` returns
///   false when the user has cancelled; a plugin that never calls it cannot be
///   interrupted, exactly as in TC.
/// - **Plugins never present windows.** Every prompt is host-rendered through
///   `request`, so an out-of-process plugin cannot own UI in the host's window
///   space — and the host's own translations are used.
public protocol PluginHostServices: Sendable {
    /// Progress for a running operation. Returns false once the user has
    /// cancelled: the plugin must then stop and report `.cancelled`.
    func report(_ progress: PluginProgress) async -> Bool

    /// A line for the operation log (TC's LogProc).
    func log(_ event: PluginLogEvent) async

    /// Asks the user something. Nil means they dismissed it — the plugin must
    /// treat that as a cancel, never as an empty answer.
    func request(_ prompt: PluginPrompt) async -> String?

    /// The password store (TC's CryptProc against its master-password vault).
    /// tc4mac backs this with the Keychain or the passphrase vault; a plugin
    /// never persists credentials itself.
    func secret(_ operation: PluginSecretOperation) async throws -> String?
}

/// How far along an operation is. `bytesTransferred` is cumulative for the
/// current item; a plugin that cannot measure bytes may send `percent` alone.
public struct PluginProgress: Sendable, Equatable {
    public var source: String
    public var destination: String?
    public var bytesTransferred: Int64?
    public var totalBytes: Int64?
    /// 0…100 when the plugin knows it, nil for indeterminate work.
    public var percent: Int?

    public init(
        source: String, destination: String? = nil,
        bytesTransferred: Int64? = nil, totalBytes: Int64? = nil, percent: Int? = nil
    ) {
        self.source = source
        self.destination = destination
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.percent = percent
    }
}

/// TC's MSGTYPE_* set, minus the ones that only make sense for its own UI.
public struct PluginLogEvent: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case connect
        case disconnect
        case details
        case transferComplete
        case operationComplete
        case importantError
    }

    public var kind: Kind
    public var message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// The RT_* request kinds. `title` and `message` are optional: leaving them
/// empty gets the host's own translated wording, which is why TC tells plugin
/// authors to pass an empty CustomText.
public struct PluginPrompt: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case userName
        case password
        case account
        case targetDirectory
        case url
        case confirmOK
        case confirmYesNo
        case confirmOKCancel
    }

    public var kind: Kind
    public var title: String?
    public var message: String?
    public var defaultValue: String?

    public init(
        kind: Kind, title: String? = nil, message: String? = nil, defaultValue: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.defaultValue = defaultValue
    }
}

/// The CryptProc operations. `loadWithoutUI` is the reason this is an enum
/// rather than a getter: TC has FS_CRYPT_LOAD_PASSWORD_NO_UI precisely so
/// that *editing* a connection never demands the master password — only
/// *using* it does.
public enum PluginSecretOperation: Sendable, Equatable {
    case save(connection: String, secret: String)
    case load(connection: String)
    case loadWithoutUI(connection: String)
    case copy(from: String, to: String)
    case move(from: String, to: String)
    case delete(connection: String)
}

/// What went wrong in a plugin call. Deliberately small and mapped onto
/// VFSError by the host adapter, so plugin failures reach the user through
/// the same one error vocabulary as everything else.
public enum PluginError: Error, Sendable, Equatable {
    case notFound(String)
    case alreadyExists(String)
    case permissionDenied(String)
    case cancelled
    case notSupported(String)
    case failed(String)
}
