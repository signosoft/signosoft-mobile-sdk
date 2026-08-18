# Changelog — SignosoftSigner (Swift)

## 0.4.2-beta

Released with `signosoft_signer` 0.4.2-beta. One fix, no API change.

- **No error message carries the `bioid` any more.** Messages built from the URL the
  WebView loaded exposed the token, which travels in that URL's query string. URLs
  in messages are now reduced to scheme, host, port and path, and every failure is
  routed through one place that strips the token from the text — including the
  message the signing shell supplies for a `sessionFailed`, which the SDK does not
  write and therefore cannot vouch for. Two tests cover both paths.

## 0.4.1-beta

Released with `signosoft_signer` 0.4.1-beta. One new public API —
`isUsableBaseURL(_:)` — plus a behaviour fix inside the view controller, a pass
over how the ceremony handles data at rest and on screen, and the first tests that
actually execute the WebView layer.

### Added

- **`SignosoftSigner.isUsableBaseURL(_:)`** — the same check `present` now runs
  before loading anything, exposed so a host can reject a misconfigured origin
  itself. A usable `baseURL` is an `https://` origin **with a host**; plain
  `http://` is usable only for `localhost`, `*.localhost`, `127.0.0.1`, `::1` and
  `10.0.2.2` while developing.

### Fixed

- **`baseURL` is validated before the ceremony loads.** An unusable origin now
  ends immediately in `.error(invalidBaseUrl)`, naming the URL. Previously it was
  loaded and failed seconds later as `loadFailed`, which blamed the network for a
  typo — `URL(string: "notaurl")` succeeds as a scheme-less relative URL, so there
  was nothing to catch it. It also means a cleartext origin never carries the
  token: such a page is not a secure context, so WebCrypto does not exist there
  and the shell could not have completed a signature over it in any case.
- **An outcome with an empty `documentToken` is a failure, not a signature.** It
  now ends in `.error(sessionFailed)`. Every other field of `SignedInfo` may
  safely default — losing a signer's middle name must not lose a signature — but
  that one is the only handle the host has on the document, and a blank one turned
  a completed ceremony into a backend call for nothing.
- **A controller that goes away without reporting now completes with
  `.cancelled`.** Until now a signer torn down without a terminal result left the
  host's completion pending forever; through the Flutter plugin that also wedged
  its "already presenting" flag, so every later `open()` answered `alreadyOpen`
  for the rest of the app's lifetime. `viewDidDisappear` now reports, keyed on
  `isBeingDismissed || isMovingFromParent` so an alert or permission prompt
  presented *over* a live ceremony does not cancel it. Reporting `.cancelled`
  there is knowingly optimistic — the source carries the comment explaining why a
  distinct `interrupted` outcome was not added. The completion still fires exactly
  once, and the controller still does not dismiss itself.

### Changed

- **Web Inspector is enabled in debug builds only.** The WebView was inspectable
  in any build; in a release build that hands anyone with the device and a USB Mac
  the token and the whole bridge — including the signer, whose identity the
  ceremony is asserting.
- **WebView storage is per-ceremony and no longer shared with the host app.** The
  ceremony runs on a non-persistent website data store, so its cookies and local
  storage neither outlive it nor are readable by any other WebView the host runs.
  The default store persists to disk and is shared app-wide, and nothing about a
  ceremony needs to survive it — every ceremony gets a fresh token.
- **The signed PDF is written with complete file protection**, so a signed medical
  document cannot be read while the device is locked. The assertion for this is
  skipped on macOS and on the Simulator, neither of which has a data-protection
  class to report; only a device run can observe it.
- **The ceremony is covered in the app-switcher snapshot.** The document and any
  signature in progress are hidden behind an opaque view when the app leaves the
  foreground, instead of being captured into the snapshot iOS shows in the task
  switcher and writes to disk.
- **The page is torn down when a result is reported.** `finish` now stops loading
  and clears the WebView's content rather than leaving the page live. This
  controller deliberately never dismisses itself, so a host that handles the
  result but forgets to flip its own presentation state would otherwise leave a
  running ceremony — possibly holding a camera or microphone stream — alive
  indefinitely.

### Added

- **Tests that run on an iOS Simulator destination**, via
  `xcodebuild test -scheme SignosoftSigner`. `swift test` runs on macOS, where
  every `#if canImport(UIKit)` source compiles out, so the WebView, the bridge
  dispatch, the timeout watchdog and the HTTP-error path had no coverage at all —
  CI's only check was that they compiled. Both gates now run on every push. No
  production code was changed to make anything testable.

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
