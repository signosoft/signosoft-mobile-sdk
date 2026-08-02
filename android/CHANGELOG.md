# Changelog — signosoft-signer (Kotlin)

## 0.4.0-alpha

First release of the Android core, ported from the Swift core in `ios/` and
released with it and `signosoft_signer` 0.4.0-alpha.

### Added

- `SignosoftSignerContract` — an `ActivityResultContract` taking a
  `SignosoftSignerRequest` and returning a `SignosoftSignerResult`. The Android
  counterpart of `SignosoftSigner.present(from:…)`, and usable unchanged from
  Compose through `rememberLauncherForActivityResult`.
- `SignosoftSigner.createIntent` / `parseResult` for hosts that drive activity
  results themselves, and `SignosoftSignerActivity` for hosts that manage
  presentation.
- `SignosoftSignerResult` — `Signed`, `Rejected`, `Cancelled`, `Failed`. Unlike
  Swift's `.error(Error)`, the failure case carries the `SignosoftErrorCode` and
  message directly; there is no `SignosoftError` type to unwrap.
- `SignosoftErrorCode` with the same ten cases as Swift and Dart. Kotlin names
  are idiomatic (`INVALID_TOKEN`) and the shared wire value lives on `wire`.
- `SignedInfo`, `BridgeMessage`, `SignedPdfStore` — direct ports, including the
  defensive field coercion, the 32 MB decoded-size ceiling, and the hardening of
  the shell-supplied filename against path traversal.
- The `@JavascriptInterface` object `SignosoftAndroid`, which is the transport
  the signing shell's `HostBridgeService` already looks for. Android receives
  the payload as a JSON string where iOS receives an object.
- `onDiagnostic` on the request — every bridge message with the signed PDF bytes
  elided to a length, carried out of the activity by a `ResultReceiver`.
- Unit tests: bridge parsing, `SignedInfo` coercion, the PDF store including
  path traversal and the ceiling, and the error-code wire format — which was
  held together by nothing but a comment across the three languages before.

### Behaviour Android needs and iOS does not

- The bridge callback arrives on a WebView worker thread and is posted to the
  main looper.
- The back button reports `Cancelled`.
- The activity declares `configChanges` so a rotation does not restart the
  ceremony.
- Camera and microphone: Android has no WebView permission prompt of its own, so
  the SDK requests the host app's runtime permission and grants the web origin
  only on success, and only for `baseUrl`'s own origin.
- `WebChromeClient.onShowFileChooser`, without which `<input type=file>` — the
  "pick an existing signature image" method — does nothing at all.
- Web contents debugging is enabled only when the host app is debuggable.

### Known gaps

- **The ceremony has never been displayed.** No emulator or device run: the code
  compiles and its unit tests pass, and nothing beyond that is verified.
- The shell's `window.SignosoftAndroid` branch has never been exercised.
- The base64 PDF crossing `@JavascriptInterface` is unmeasured at any size; the
  32 MB ceiling is carried over from iOS.
- No published Maven artifact — consumed as a local Gradle module.
- Minimum API 24, `compileSdk` 36, AGP 9.0.1, Kotlin 2.3.20, JDK 17.
