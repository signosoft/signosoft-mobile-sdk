# Changelog — signosoft_signer (Flutter)

## 0.5.0-beta

**Android is supported.** `open()` on Android now presents the ceremony instead
of resolving to `Failed(unsupportedPlatform)`.

### Added

- **The Android side of the plugin**, backed by the new Kotlin core in
  `android/` (see [its changelog](../android/CHANGELOG.md)). The Dart API is
  unchanged: the same `open()`, the same four outcomes, the same ten error
  codes, the same `onDiagnostic`.
- One `Signed` ceremony has been completed on an Android emulator against the
  hosted shell, returning a `documentToken` and a genuinely signed PDF, and
  `Cancelled` has been driven from the system back button. That is the whole of
  what has been verified live on Android — the rest of the outcomes are
  unit-tested only, and there has been **no run on a physical Android device**.
  iOS is in the same position: simulator only.

### Fixed

- **Android: ceremony data no longer outlives the ceremony.** Each ceremony runs
  in its own WebView storage partition, deleted when it ends — the same
  guarantee iOS has always made with a non-persistent data store. Your app's own
  WebView storage is never touched. Needs WebView 114 or newer, which is a
  provider question rather than a `minSdk` one; where absent, the ceremony uses
  the host's default storage as before. Because nothing is cached between
  ceremonies, every ceremony re-downloads the signing shell on both platforms.
- **Android: an outcome with an empty `documentToken` now resolves to
  `Failed(sessionFailed)`**, not `Signed`. This is what the API documented and
  what iOS already did; only Android disagreed.
- **Android: the signer's WebView is now detached before it is destroyed.**
  Destroying an attached WebView is undefined behaviour on Android and could
  take the renderer down under the compositor during teardown.

### Changed

- `unsupportedPlatform` now means neither iOS nor Android — web and desktop
  builds. Hosts that branched on it for Android will stop seeing it there.
- Doc comments and the `notRegistered` message say "native app" rather than
  "iOS app".

### Still open

- No physical-device run on either platform.
- Camera-based signature methods remain unverified everywhere: they cannot run
  on the iOS Simulator, and they were not exercised on the Android emulator.
- Handwritten (signature-pad) fields still cannot be completed from
  `https://www.signosoft.com/mobilesdk/` — a server-side licence-allowlist
  issue, unchanged by this release and identical on both platforms.

## 0.4.3-beta

First beta. **No API change** — every 0.3 call site compiles unmodified. Behaviours
the documentation promised and the code did not honour now do, no error message can
leak the signing token, the shell has an address you can pass, and the layer that
drives the WebView has tests for the first time.

### Fixed

- **No error message carries the `bioid`.** A failure raised after the shell had
  been reached built its message from the URL the SDK loaded, and the token travels
  in that URL's query string. Since a `bioid` is a credential that signs the
  document, and since this guide asks you to send us the message when reporting a
  bug, that would have put a working credential into bug reports and device logs.
  URLs in messages now carry scheme, host, port and path only, and the token is
  stripped from every message on the way out — including messages written by the
  signing shell rather than by the SDK.

- **`open()` really never throws.** It is documented never to throw, and it
  could: the channel translated `PlatformException` and `MissingPluginException`
  only, so anything else — a codec error, for instance — escaped into the
  caller's `await`. A catch-all now returns `Failed(unknown, …)`; the specific
  error codes are unchanged. A host `onDiagnostic` callback that throws can no
  longer affect the session either.
- **A signer that disappears without reporting now answers `Cancelled`.** If the
  ceremony was torn down without a terminal result — the host popping its own
  navigation stack, for example — the `Future` from `open()` never completed, and
  because the plugin still believed a ceremony was on screen, *every* later
  `open()` returned `Failed(alreadyOpen)` for the rest of the app's lifetime.
  A ceremony interrupted this way is reported as `Cancelled`, which is
  deliberately optimistic: it is the outcome a host can act on, and the Swift
  side keeps a comment explaining why no separate `Interrupted` variant was
  added. An alert or permission prompt presented *over* a live ceremony does not
  cancel it.

### Changed

- **`baseUrl` is validated before the ceremony opens.** It must be an `https://`
  origin with a host; plain `http://` is accepted only for `localhost`,
  `*.localhost`, `127.0.0.1`, `::1` and `10.0.2.2` while developing. Anything else
  resolves to `Failed(invalidBaseUrl)` immediately, before the signer appears,
  instead of loading and failing seconds later as `loadFailed` — which blamed the
  network for what was usually a typo. A public `http://` origin is now rejected
  outright rather than attempted: it is not a secure context, so WebCrypto does
  not exist there and a signature could never have completed over it. This
  supersedes the guidance that a LAN IP over plain HTTP works for development on a
  device; serve the shell over `https://` instead.
- **An outcome carrying an empty `documentToken` resolves to
  `Failed(sessionFailed)`, not `Signed`.** Parsing still tolerates every other
  missing or mistyped field on purpose — a malformed middle name must never lose a
  completed signature — but `documentToken` is the only handle a host has on the
  document, so a blank one turned a finished ceremony into a backend call for
  nothing. A loud failure beats a hollow success.
- **The signing shell is hosted.** `baseUrl` is
  `https://www.signosoft.com/mobilesdk/`; the READMEs, both guides and the
  examples now name it instead of telling integrators to ask for a URL. This
  supersedes the "signing shell is not hosted" entry under 0.3.0-alpha, which was
  true when written. The parameter stays required — no API change.
- The Medicly example defaults `BASE_URL` to that origin, so a run needs only
  `--dart-define=BIOID=…`. The plugin example prefills its `baseUrl` field.
- **The Medicly example is usable on a phone.** Below 900pt the header overflowed,
  nothing scrolled and the Sign button could not be reached at all — invisible on
  an iPad, which is why it went unnoticed. Text scaling is now pinned per Material
  width class, so the iPad's across-the-room 2x is preserved exactly while a phone
  gets a compact toolbar, a height-capped panel that scrolls inside its own box,
  and a Sign button that cannot be scrolled away.
- **The bare `example/` no longer looks like a broken SDK.** Its Sign button was
  enabled with an empty token, so tapping it returned `Failed(invalidToken)`; it
  is now disabled until a token is present and says why. The outcome card passed a
  translucent tint to an elevated `Card`, which paints through a shape layer that
  ignores alpha — it rendered as a solid slab with an unreadable title, and the
  tint is now blended down to an opaque colour. The keyboard is dismissed before
  signing, since on a phone the result renders behind it.
- The client guides describe what the SDK actually does today: the handwritten
  signature-field limitation with its cause and its remedies, the demo's width
  classes, and the fact that no run on physical hardware has happened yet.

### Added

- **The iOS view-controller layer is tested.** `swift test` runs on macOS, where
  every `#if canImport(UIKit)` source compiles out, so the WebView, the bridge
  dispatch, the timeout watchdog and the HTTP-error path had no coverage beyond
  "it compiles". They now run on an iOS Simulator destination in CI on every
  push. No production code was changed to make them testable.
- First widget tests for both examples — the Medicly layout at phone and tablet
  widths, and the bare example's four outcomes and its guarded Sign button.

### Still open

- `downloadUrl` remains null; fetch the PDF server-side with `documentToken`.
- **The handwritten (pad) signature field cannot be completed** from the hosted
  shell. The pad's driver is gated by an origin allowlist carried in its licence,
  and the shell's origin is not on it — so the pad reports a connection error and
  Confirm stays disabled. Reproduced in a plain desktop browser, so it is neither
  the SDK nor the WebView. Both remedies are server-side and need no code from
  you; use the typed `simple` field, whose Draw tab also accepts a handwritten
  signature. `docs/INTEGRATION.md` has the detail.
- `Rejected` is unit-tested on all three layers but still never exercised end to
  end.
- Simulator only — no physical-device, camera or hardware-pad verification. It is
  planned, not done.

## 0.3.0-alpha

Distribution release. **No API change** — every 0.2 call site compiles unmodified.
0.2 was installable only by unpacking an archive; 0.3 is a repository you can
depend on, and the archive route is gone.

### Added

- **`git:` installation** from `github.com/signosoft/signosoft-mobile-sdk`:

  ```yaml
  signosoft_signer:
    git:
      url: git@github.com:signosoft/signosoft-mobile-sdk.git
      ref: v0.4.3-beta
      path: signosoft_signer
  ```

  Pub clones the whole repository, so the plugin's symlink to the sibling Swift
  core resolves inside the clone. Verified from a Flutter app in a directory that
  has never seen the SDK source tree: `flutter pub get`, a simulator build, and
  a live `Failed(invalidToken)` round trip through the plugin and the Swift core.
- **`examples/medicly/`** — a realistic iPad host app (patient, report, Sign
  button, signed PDF rendered on return), previously internal to Signosoft. The
  bare `signosoft_signer/example/` stays as the minimal reference.
- Continuous integration in the repository: Swift core tests, plugin analyze /
  format / test, and a simulator build of the example — the only check that
  exercises the plugin, the symlink and Swift Package Manager together the way a
  customer's build does. Plus an issue template that asks for the error code and
  diagnostics, and warns against pasting a `bioid`.

### Changed

- **`LICENSE` is now the Signosoft proprietary commercial licence.** 0.2 shipped a
  "pending legal review" placeholder. Use of the SDK requires a paid commercial
  agreement and an active Signosoft service account; it is not licensed for
  redistribution.
- The Medicly example reads its `bioid` and shell origin from
  `--dart-define=BIOID=… --dart-define=BASE_URL=…` rather than constants. No live
  token is committed anywhere in the distribution.
- `docs/INTEGRATION.md` §3 leads with the `git:` route; `docs/GETTING-STARTED.md`
  lists repository access as something to obtain from Signosoft before starting.

### Still open

Unchanged from 0.2, and all of it is outside the packages:

- **The signing shell is not hosted.** `baseUrl` stays required — there is still
  no URL a customer can pass. This is the one thing blocking a pilot.
- `downloadUrl` remains null; fetch the PDF server-side with `documentToken`.
- `Rejected` is unit-tested on all three layers but never exercised end to end.
- Simulator only — no physical-device or camera verification.

## 0.2.0-alpha

Second alpha. The package is now installable and testable outside Signosoft's own
codebase, and every failure is machine-readable.

Both packages now carry the **same** version string. 0.1 shipped the Swift core
as `0.1.0-alpha` and the plugin as `0.1.0-alpha.1`, which was drift waiting to
happen — they are released together and are now numbered together.

### Added

- `SignosoftErrorCode` on `Failed` — `invalidToken`, `invalidBaseUrl`,
  `loadFailed`, `loadTimeout`, `sessionFailed`, `alreadyOpen`, `noPresenter`,
  `unsupportedPlatform`, `notRegistered`, `unknown`. Branch on the code; the
  message is for developers.
- `loadTimeout` parameter on `open()` (default 45s). Without it an unreachable
  `baseUrl` left the signer on a blank screen indefinitely.
- `onDiagnostic` callback on `open()` — every bridge message, with the signed
  PDF bytes elided to a length. Diagnostic only, explicitly not API.
- `example/` — a minimal integration app: token field, base URL field, Sign
  button, all four outcomes rendered.
- Unit tests (`flutter test`): reply parsing for every status, malformed and
  mistyped payloads, error-code mapping, missing plugin, diagnostics.

### Changed

- **Breaking.** `Failed` now takes a code: `Failed(SignosoftErrorCode, String)`.
  Destructuring by name is unaffected — `case Failed(:final message)` still
  compiles.
- **Breaking.** A non-iOS platform returns `Failed(unsupportedPlatform, …)`
  instead of throwing `UnsupportedError`. `open()` now never throws.
- `Signed` and `Rejected` share a new intermediate sealed class,
  `SignosoftOutcome`, which declares the nine common metadata fields once. All
  field names and types are unchanged, so existing patterns keep working.
- Result classes are now `final`; the sealed hierarchy was never meant to be
  extended outside the package.
- A `downloadUrl` that is empty, unparseable or scheme-less now arrives as null
  rather than as an unusable `Uri`.
- Library split into `lib/src/{signer,channel,models/}`; the public surface is
  unchanged and still exported from `package:signosoft_signer/signosoft_signer.dart`.
- Honest SDK constraints: `sdk: >=3.12.0 <4.0.0`, `flutter: >=3.44.0`. The old
  `flutter: >=3.3.0` was wrong — the package needs Dart 3 sealed classes and
  Flutter's Swift Package Manager support.
- `LICENSE` replaced the `flutter create` placeholder with an explicit
  "pending legal review, not licensed for redistribution" notice.
- `PrivacyInfo.xcprivacy` filled in and actually bundled — verified present in a
  built `.app`.

### Removed

- **The CocoaPods podspec.** CocoaPods discards source files whose real path
  escapes the pod root, so the shared Swift core could never be compiled into
  the pod; the fallback had never successfully built. Flutter 3.44+ with Swift
  Package Manager is the supported and tested route.

### Still open

- `downloadUrl` remains null — blocked on a backend decision. Fetch the PDF
  server-side with `documentToken`.
- No `downloadSignedPdf()` helper, for the same reason.
- `Rejected` is unit-tested on all layers but not exercised end to end; the
  reject control is not rendered for the test tenant.
- Simulator only — no physical-device or camera verification.

## 0.1.0-alpha.1

First packaged release of the Dart binding. `publish_to: none`; consumed by local path.

### Added

- `SignosoftSigner.open({required String token, required Uri baseUrl})`.
- Sealed result type: `Signed`, `Rejected`, `Cancelled`, `Failed`.
- `Signed.signedPdfPath` — the finished PDF on disk, when the shell could fetch it.
- `Signed.downloadUrl` — modelled, always null today.
- iOS implementation over `MethodChannel("com.signosoft.signer")`, backed by the
  `SignosoftSigner` Swift package.

### Behaviour worth knowing

- `open()` never throws for a signing outcome. A `PlatformException` from the platform side
  becomes `Failed(message)`; a missing plugin registration becomes `Failed` too.
- Android throws `UnsupportedError` — deliberately not a silent stub.
- A second concurrent `open()` is rejected while a ceremony is on screen.

### Known gaps

- iOS only. iOS 16.0 minimum.
- No `downloadSignedPdf()` helper — blocked on the backend download-URL decision.
- `Rejected` is implemented but not yet exercised end to end.
- CocoaPods fallback shipped but unverified; Swift Package Manager is the tested path.
