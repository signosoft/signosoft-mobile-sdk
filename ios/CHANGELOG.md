# Changelog — SignosoftSigner (Swift)

## 0.4.0-alpha

Released with `signosoft_signer` 0.4.0-alpha. **No source change in this
package** — the release adds an Android core beside it.

### Changed

- A Kotlin port of this package now lives in `android/`, and
  `SignosoftErrorCode`'s raw values are shared with it as well as with Dart. A
  test in the Kotlin core pins all three lists against each other; nothing but a
  comment did before.
- Documentation is per platform. Known limitations now separates what is
  verified here — which is everything it listed before — from the much shorter
  Android list.

## 0.3.0-alpha

Released with `signosoft_signer` 0.3.0-alpha. **No source change in this package** —
the release is about how it is distributed.

### Changed

- **`LICENSE` is now the Signosoft proprietary commercial licence**, replacing the
  "pending legal review" placeholder.
- The package now ships inside a git repository
  (`github.com/signosoft/signosoft-mobile-sdk`) rather than in a release archive.
  Native iOS consumers still add `ios/` as a local Swift package after cloning;
  nothing about `Package.swift` or the module changes.
- Repository CI runs `swift test` on every push.

## 0.2.0-alpha

Released together with `signosoft_signer` 0.2.0-alpha, and from now on sharing
its version string.

### Added

- `SignosoftErrorCode` on `SignosoftError`, so hosts can branch on a failure
  rather than parse a string. Raw values are the wire format shared with the
  Flutter plugin.
- `loadTimeout` on `SignosoftSigner.present` and `SignosoftSignerViewController`
  (default 45s) — a `baseURL` that is reachable but never becomes interactive now
  ends in `.error(loadTimeout)` instead of a permanently blank screen. Verified:
  before this, an unreachable host hung indefinitely.
- `onEvent:` parameter on `SignosoftSigner.present`, matching the view
  controller's existing diagnostic tap.
- HTTP response-status handling: a main-frame response of 400 or above ends the
  session with `loadFailed` and names the status and URL. A misconfigured host
  usually *answers* — with a 404 or a 502 — rather than refusing, so without this
  the signer sat on the host's error page until the timeout expired.
- `didFail(navigation:withError:)` alongside the existing provisional handler.
- `webViewWebContentProcessDidTerminate` → `.error(loadFailed)`, rather than a
  white screen after the WebView's content process is killed.
- `PrivacyInfo.xcprivacy`, declared as a package resource and verified present in
  a built product.
- `Tests/SignosoftSignerTests` — bridge-message parsing, `SignedInfo` field
  coercion, and the PDF store including path traversal and the size ceiling.
- `LICENSE`.

### Changed

- **Breaking.** `SignosoftError(message:)` is now
  `SignosoftError(code:message:)`.
- Sources split into `Model/` (Foundation-only: `SignedInfo`,
  `SignosoftSignerResult`, `SignosoftError`, `BridgeMessage`, `SignedPdfStore`)
  and `UI/` (`SignosoftSignerViewController`, `WeakScriptMessageHandler`).
  `SignosoftSignerSheet` moved to its own file. The public API is unchanged apart
  from the two additions above.
- The package now also declares `.macOS(.v13)`, and every UIKit source is behind
  `#if canImport(UIKit)`. This exists purely so `swift test` runs the model and
  parsing tests on a Mac with no simulator; iOS remains the product platform.
- Bridge-message parsing and PDF writing moved out of the view controller into
  `BridgeMessage` and `SignedPdfStore`, which is what made them testable.
- `SignedPdfStore` enforces a 32 MB decoded-size ceiling and hardens the
  shell-supplied filename against path traversal. Above the ceiling the signature
  still succeeds and `signedPdfFileURL` is nil — measured: WebKit itself carried a
  50 MB document (69,905,064 base64 characters) across the bridge intact, so the
  ceiling is a memory guard, not a bridge limit.
- Diagnostic events elide `pdfBase64`, reporting `pdfBase64Length` instead.
- A `downloadUrl` that is empty or scheme-less is now nil rather than an
  unusable `URL`.

### Unchanged, and deliberately so

- The script message handler is still registered through a **weak proxy**.
  `WKUserContentController` retains its handler, so registering the controller
  directly leaks it and `deinit` never runs.
- The controller still **reports but never dismisses itself** — the caller owns
  presentation, which is what makes `SignosoftSignerSheet` usable inside
  `.fullScreenCover`.
- The completion still fires exactly once.

## 0.1.0-alpha

First packaged release of the Swift core, extracted from an internal proof of concept.
Not published anywhere; consumed by local path.

### Added

- `SignosoftSigner.present(from:token:baseURL:completion:)` — presents the signing ceremony
  in a full-screen `WKWebView` and reports a typed `SignosoftSignerResult`.
- `SignosoftSignerSheet` — SwiftUI `UIViewControllerRepresentable` for `.fullScreenCover`.
- `SignedInfo` with the completion metadata, plus `downloadUrl` and `signedPdfFileURL`
  (both optional).
- `SignosoftSignerViewController` exposed publicly for hosts that manage presentation
  themselves.

### Known gaps

- `downloadUrl` is always nil — no backend design chosen. Hosts must call `downloadDoc` with
  `documentToken` from their own backend.
- iOS 16.0 minimum.
- Camera-based signature methods untested (not possible on the Simulator).
- No Bank iD / external IdP hop-out.
