import Foundation

/// Describes one field a content provider offers (Plugin System §3.4 —
/// the WDX-equivalent surface: custom columns, searchable fields, and
/// MultiRename `[=field]` placeholders all resolve through these).
public struct FieldDescriptor: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case text
        case number
        /// Fractional (WDX `ft_numeric_floating`).
        case decimal
        /// Yes/no (WDX `ft_boolean`).
        case boolean
        case date
    }

    public var id: FieldID
    public var displayName: String
    public var kind: Kind

    public init(id: FieldID, displayName: String, kind: Kind) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
    }
}

/// One source of field values — a built-in provider, a test double, or (next
/// slices) an ExtensionKit-backed plugin adapter. Mechanism-agnostic on
/// purpose (ADR-006): the pipeline neither knows nor cares where values come
/// from.
public protocol ContentProvider: Sendable {
    /// Stable identifier, used to attribute fields ("builtin.fileinfo",
    /// plugin manifest id for plugins).
    var providerID: String { get }
    func fields() -> [FieldDescriptor]
    /// Nil when the field does not apply to this file (a column shows blank).
    func value(of field: FieldID, forFileAt url: URL) async throws -> FieldValue?
}
