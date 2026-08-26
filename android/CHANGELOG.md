# Changelog — signosoft-signer (Kotlin)

## 0.5.0-beta

First release of the Android core, ported from the Swift core in `ios/` and
released with it and `signosoft_signer` 0.5.0-beta.

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

### Verified

On the Pixel 7 emulator (API 36, `google_apis`, arm64), against
`https://www.signosoft.com/mobilesdk/`, on 2026-08-26:

- **`Signed` end to end.** A typed signature field on a single-field document,
  driven from `examples/medicly`. The host received a `documentToken`, and the
  PDF written to the app cache carries `/Type /Sig`,
  `/SubFilter /ETSI.CAdES.detached` and a two-range `/ByteRange`. Reproduced
  four times on separate documents and freshly minted tokens — three on a Pixel 7
  phone emulator and one on a Pixel Tablet emulator (2560×1600, 320 dpi), where
  the ceremony, the signature dialog and the error state all lay out correctly.
- **The typed field's *Draw* tab** — a finger-drawn signature. Touch events
  reach the WebView canvas, the ink renders, and the signed PDF comes back the
  same way.
- **The shell's `window.SignosoftAndroid` branch works.** The hosted shell calls
  `postMessage` with a JSON **string**, which is what `SignosoftBridge` reads;
  `ready` and `signed` both arrived and dispatched to the main looper.
- **`Cancelled` from the system back button.**
- The signed PDF crossing `@JavascriptInterface` in one call — 896 KB, about
  1.19 M base64 characters — and reaching the host as a local file under the
  shell-supplied name.

### Fixed

- **`WebView.destroy()` was called while the WebView was still in the view
  tree.** Android logs *"destroy() called while WebView is still attached to
  window"* for this and leaves the outcome undefined — the renderer can be torn
  down under the compositor. `onDestroy` now stops loading, drops the chrome
  client, removes the WebView from its parent and only then destroys it. Found
  on an emulator teardown after a `loadTimeout`; the warning is gone and the
  renderer process now exits cleanly.

### Known gaps

- **No physical device run.** Everything above is the emulator. This is not a
  weaker position than iOS, which has had no device run either.
- **The WebView is not isolated per ceremony, and iOS's is.** iOS gives each
  ceremony a non-persistent `WKWebsiteDataStore`; this core uses the host app's
  default WebView profile, so cookies, local storage and cached assets outlive
  the ceremony and are shared with the host's other WebViews. Deliberate for now
  and documented in the integration guide's privacy section — it makes repeat
  opens much faster — but it is a real divergence and the condition behind the
  stale-cache `DOC_LINK_NOT_EXIST` symptom that the iOS change removed.
- **Emulator load times are not representative, and real-device load time is
  unmeasured.** A first ceremony on a freshly booted emulator timed out at
  45.3 s; later opens reached `ready` in 15–20 s. Profiling put the cost in the
  emulator's network stack — about 1 s per request there against about 50 ms
  from the host, over the 35–50 requests the shell makes. WebView startup
  (0.1–0.4 s), renderer CPU (2.35 s across a 20 s load), bandwidth (33 Mbps over
  the emulator NAT) and GPU backend were each measured and excluded.
- Camera and microphone permission handling and `onShowFileChooser` have still
  never run. Camera-based signature methods are unverified here as on iOS.
- Only `Signed` and `Cancelled` have been observed live. `loadTimeout`,
  `loadFailed`, `invalidToken` and `sessionFailed` are unit-tested only, as is
  the shell's own close button.
- The base64 PDF is measured at 896 KB and nowhere near the ceiling; the 32 MB
  limit is still carried over from iOS unmeasured.
- Rotation, backgrounding and low-memory renderer kills are untested.
- No published Maven artifact — consumed as a local Gradle module.
- Minimum API 24, `compileSdk` 36, AGP 9.0.1, Kotlin 2.3.20, JDK 17.
