import Foundation

/// The one origin the signer trusts: the one serving the shell.
///
/// Today it answers a single question — whether a `baseUrl` is loadable at all —
/// which is what stops a typo from being reported as a network failure seconds
/// later, and what stops a cleartext origin from ever carrying the bioid.
///
/// It models a whole origin rather than just a scheme test because same-origin
/// comparison is the check the bridge and the navigation delegate still need;
/// `matches(_:)` is here, tested, and deliberately not yet wired into either.
/// Doing that changes behaviour in a live ceremony and has to be verified
/// against a real session first.
///
/// Deliberately free of WebKit and UIKit: the enum `SignosoftSigner` lives
/// behind `#if canImport(UIKit)` and so does not exist under `swift test`.
/// Keeping this type clean is what makes it testable on macOS at all.
struct ShellOrigin: Equatable, CustomStringConvertible {
    let scheme: String
    let host: String
    let port: Int

    var description: String { "\(scheme)://\(host):\(port)" }

    /// Nil when the URL has no scheme or no host — the same inputs `isUsable`
    /// rejects, minus the transport rule.
    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty
        else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = Self.effectivePort(url.port, scheme: scheme)
    }

    /// Takes the pieces of a `WKSecurityOrigin`, so the caller can stay the only
    /// part that imports WebKit.
    init(scheme: String, host: String, port: Int) {
        self.scheme = scheme.lowercased()
        self.host = host.lowercased()
        self.port = Self.effectivePort(port, scheme: scheme)
    }

    /// True when `other` is the same origin by scheme, host and port — the same
    /// comparison the web platform makes.
    func matches(_ other: ShellOrigin?) -> Bool { self == other }

    func matches(url: URL?) -> Bool {
        guard let url else { return false }
        return matches(ShellOrigin(url: url))
    }

    /// `WKSecurityOrigin.port` reports 0 for a scheme's default port and
    /// `URL.port` reports nil, so both have to be normalised before comparing.
    private static func effectivePort(_ port: Int?, scheme: String) -> Int {
        if let port, port != 0 { return port }
        return scheme.lowercased() == "http" ? 80 : 443
    }

    /// Whether the signer can load this origin at all.
    ///
    /// `URL(string: "notaurl")` succeeds — it becomes a scheme-less relative
    /// URL — so without this the ceremony opened, failed to load, and reported
    /// `loadFailed` seconds later, blaming the network for a typo.
    ///
    /// Plain HTTP is only ever a locally served development shell. A public
    /// `http://` origin would put the bioid on the wire in cleartext, and the
    /// shell could not complete a signature over it anyway: such a page is not
    /// a secure context, so WebCrypto does not exist there.
    static func isUsable(_ url: URL) -> Bool {
        guard let origin = ShellOrigin(url: url) else { return false }
        return origin.scheme == "https"
            || (origin.scheme == "http" && isLoopbackHost(origin.host))
    }

    /// `10.0.2.2` is the Android emulator's route to the host machine. Accepted
    /// here too, so one baseUrl behaves the same on both platforms.
    static func isLoopbackHost(_ host: String) -> Bool {
        switch host {
        case "localhost", "127.0.0.1", "::1", "[::1]", "10.0.2.2": return true
        default: return host.hasSuffix(".localhost")
        }
    }
}
