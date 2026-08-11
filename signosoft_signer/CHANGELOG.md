# Changelog — signosoft_signer (Flutter)

## Unreleased

### Changed

- **The signing shell is hosted.** `baseUrl` is
  `https://www.signosoft.com/mobilesdk/`; the READMEs, both guides and the
  examples now name it instead of telling integrators to ask for a URL. This
  supersedes the "signing shell is not hosted" entry under 0.3.0-alpha, which was
  true when written. The parameter stays required — no API change.
- The Medicly example defaults `BASE_URL` to that origin, so a run needs only
  `--dart-define=BIOID=…`. The plugin example prefills its `baseUrl` field.

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
      ref: v0.3.0-alpha
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
