import Foundation

/// Wire DTO for a field descriptor crossing the host↔plugin boundary
/// (Plugin System §2/§3.4). JSON payloads keep the @objc XPC protocol simple
/// and stable across plugin/host versions.
public struct FieldDescriptorDTO: Codable, Sendable {
    public var id: String
    public var displayName: String
    public var kind: String

    public init(_ descriptor: FieldDescriptor) {
        id = descriptor.id.rawValue
        displayName = descriptor.displayName
        kind = descriptor.kind.rawValue
    }

    /// Back to the domain type; nil if the plugin sent an unknown kind.
    public var descriptor: FieldDescriptor? {
        guard let kind = FieldDescriptor.Kind(rawValue: kind) else { return nil }
        return FieldDescriptor(id: FieldID(rawValue: id), displayName: displayName, kind: kind)
    }
}

/// Wire DTO for one resolved field value.
public struct FieldValueDTO: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case text, number, decimal, boolean, date }
    public var kind: Kind
    public var text: String?
    public var number: Int64?
    public var decimal: Double?
    public var boolean: Bool?
    public var date: Date?
    /// Optional display string for a fractional value ("12.2 MP").
    public var display: String?

    public init(_ value: FieldValue) {
        switch value {
        case .text(let text): kind = .text; self.text = text
        case .number(let number): kind = .number; self.number = number
        case .decimal(let number, let display):
            kind = .decimal
            self.decimal = number
            self.display = display
        case .boolean(let flag): kind = .boolean; self.boolean = flag
        case .date(let date): kind = .date; self.date = date
        }
    }

    public var value: FieldValue? {
        switch kind {
        case .text: return text.map(FieldValue.text)
        case .number: return number.map(FieldValue.number)
        case .decimal: return decimal.map { FieldValue.decimal($0, display: display) }
        case .boolean: return boolean.map(FieldValue.boolean)
        case .date: return date.map(FieldValue.date)
        }
    }
}

/// The XPC service a content plugin exports (Plugin System §2 wire protocol,
/// ADR-006). The ExtensionKit process gives the host an NSXPCConnection whose
/// remote object conforms to this; payloads are JSON `Data` so the interface
/// stays versioned and simple. The process-spawn glue is a later slice — this
/// is the contract both sides compile against.
@objc public protocol ContentProviderXPCProtocol {
    /// JSON-encoded `[FieldDescriptorDTO]` — the fields this plugin offers.
    func fetchFields(withReply reply: @escaping (Data) -> Void)
    /// JSON-encoded `FieldValueDTO`, or nil when the file has no value for the
    /// field. The plugin reads the file itself from `path` (handle-passing for
    /// bulk content comes with the viewer/packer types).
    func fetchValue(
        forField fieldID: String, path: String, withReply reply: @escaping (Data?) -> Void)
}

/// Host-side adapter presenting an out-of-process plugin as a ContentProvider,
/// so it drops into the FieldPipeline exactly like a built-in. Descriptors are
/// fetched once when the host connects (they are static per plugin); values
/// resolve on demand over the wire.
public final class XPCContentProvider: ContentProvider, @unchecked Sendable {
    public let providerID: String
    private let descriptors: [FieldDescriptor]
    // An XPC remote proxy (or a test double). XPC proxies are safe to message
    // from concurrent tasks, so @unchecked Sendable holds here.
    private let remote: any ContentProviderXPCProtocol

    public init(
        providerID: String,
        descriptors: [FieldDescriptor],
        remote: any ContentProviderXPCProtocol
    ) {
        self.providerID = providerID
        self.descriptors = descriptors
        self.remote = remote
    }

    /// Decodes the field list a plugin advertises — the host calls this once
    /// (awaiting the XPC round-trip) before constructing the provider.
    public static func fetchDescriptors(
        from remote: any ContentProviderXPCProtocol
    ) async -> [FieldDescriptor] {
        let data: Data = await withCheckedContinuation { continuation in
            remote.fetchFields { continuation.resume(returning: $0) }
        }
        let dtos = (try? JSONDecoder().decode([FieldDescriptorDTO].self, from: data)) ?? []
        return dtos.compactMap(\.descriptor)
    }

    public func fields() -> [FieldDescriptor] { descriptors }

    public func value(of field: FieldID, forFileAt url: URL) async throws -> FieldValue? {
        let data: Data? = await withCheckedContinuation { continuation in
            remote.fetchValue(forField: field.rawValue, path: url.path) {
                continuation.resume(returning: $0)
            }
        }
        guard let data,
              let dto = try? JSONDecoder().decode(FieldValueDTO.self, from: data) else {
            return nil
        }
        return dto.value
    }
}
