import Foundation

/// Identifies a content-plugin column (Phase 4); reserved now so VFSEntry's shape is stable.
public struct FieldID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// One resolved content-field value. The cases mirror the WDX field types a
/// plugin may declare (`ft_string`, `ft_numeric_32/64`, `ft_numeric_floating`,
/// `ft_boolean`, `ft_datetime`) — a fractional value like megapixels or an
/// aperture, and a yes/no like "has transparency", cannot be told honestly as
/// text: sorting and searching need the underlying number.
public enum FieldValue: Hashable, Codable, Sendable {
    case text(String)
    case number(Int64)
    /// Carries an optional display string (WDX lets a floating field append
    /// one) so "12.2 MP" shows while 12.2 drives sort and comparison.
    case decimal(Double, display: String? = nil)
    case boolean(Bool)
    case date(Date)
}
