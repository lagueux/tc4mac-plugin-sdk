import Foundation

/// A viewer plugin (Plugin System §3.3 — the WLX equivalent): a new content
/// type for Lister (F3) and Quick View (Ctrl+Q).
///
/// WLX hands back an `HWND` that Total Commander reparents into its own
/// window — a shared-address-space design with no isolation, which macOS does
/// not offer an out-of-process equivalent to without remote-view plumbing.
/// So the contract is inverted: a plugin **converts** the file into something
/// the host already renders well. That covers most real WLX plugins, and it
/// hands them the host's own find, print, copy, scroll position, and
/// appearance for free rather than each reimplementing them.
///
/// A plugin that must draw and interact itself needs the remote-view tier;
/// that is deliberately not in this version, because a half-built one would
/// be worse than an honest absence.
public protocol ViewerPlugin: Sendable {
    /// Whether this plugin wants the file, and how strongly. The host asks
    /// only after its own built-in modes decline, and takes the highest
    /// priority — the user's per-extension override still wins over all.
    ///
    /// `prefix` is the first 8 KB, the same window WLX detect strings get, so
    /// a plugin can sniff magic bytes without opening the file itself.
    func priority(forFileAt url: URL, prefix: Data) async -> ViewerPriority

    /// Converts the file into something the host renders. Throwing here
    /// leaves Lister on its built-in text/hex view rather than showing an
    /// error page.
    func render(fileAt url: URL, options: ViewerOptions) async throws -> ViewerContent

    /// A panel thumbnail. Independent of `render`: a plugin may implement
    /// only this (WLX allows a thumbnail-only plugin, and it is the cheapest
    /// useful thing a format plugin can do). The host asks only when
    /// QuickLook has no thumbnail of its own.
    func thumbnail(forFileAt url: URL, maxSize: CGSize, prefix: Data) async -> Data?
}

public extension ViewerPlugin {
    func priority(forFileAt url: URL, prefix: Data) async -> ViewerPriority { .decline }
    func render(fileAt url: URL, options: ViewerOptions) async throws -> ViewerContent {
        throw PluginError.notSupported("This plugin does not display files.") // l10n:exempt: boundary key
    }
    func thumbnail(forFileAt url: URL, maxSize: CGSize, prefix: Data) async -> Data? { nil }
}

/// How much a plugin wants a file. Ordered, so the host can simply take the
/// maximum.
public enum ViewerPriority: Int, Sendable, Comparable, Codable {
    /// Not mine.
    case decline = 0
    /// I can show it, but a built-in or QuickLook is probably better —
    /// a generic fallback (hex, plain text).
    case fallback = 1
    /// This is my format.
    case preferred = 2
    /// Show me even where the host has a built-in view (WLX's FORCE).
    case force = 3

    public static func < (lhs: ViewerPriority, rhs: ViewerPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What a plugin hands back for the host to display. Each case is something
/// tc4mac's viewer already renders, with find, print, and copy attached.
public enum ViewerContent: Sendable, Equatable {
    /// Plain text — gets the viewer's font, wrap, and search.
    case text(String)
    /// Rich text as RTF data, for syntax highlighting or styled documents.
    case richText(Data)
    /// Markup the host renders read-only. Local resources are not loaded:
    /// a converted document must be self-contained.
    case html(String)
    /// Image data in any format ImageIO reads.
    case image(Data)
    /// A PDF, which also gives printing and page navigation.
    case pdf(Data)
    /// Key/value rows — the natural shape for metadata dumps, and the reason
    /// a properties-style plugin needs no drawing code at all.
    case properties([ViewerProperty])
}

/// One labelled row of a `.properties` view, optionally grouped under a
/// heading ("Camera", "GPS").
public struct ViewerProperty: Sendable, Equatable {
    public var group: String?
    public var name: String
    public var value: String

    public init(group: String? = nil, name: String, value: String) {
        self.group = group
        self.name = name
        self.value = value
    }
}

/// The WLX show-flags that survive on macOS. The charset trio is gone (one
/// scalable font), and both dark-mode flags are gone (appearance is
/// inherited).
public struct ViewerOptions: OptionSet, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// lcp_wraptext
    public static let wrapText = ViewerOptions(rawValue: 1 << 0)
    /// lcp_fittowindow
    public static let fitToWindow = ViewerOptions(rawValue: 1 << 1)
    /// lcp_fitlargeronly
    public static let fitLargerOnly = ViewerOptions(rawValue: 1 << 2)
    /// lcp_center
    public static let center = ViewerOptions(rawValue: 1 << 3)
    /// Quick View rather than a full Lister window: the plugin may render a
    /// cheaper view, since the cursor moves through files quickly.
    public static let quickView = ViewerOptions(rawValue: 1 << 4)
}
