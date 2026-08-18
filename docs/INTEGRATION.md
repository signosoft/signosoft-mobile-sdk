# Integration guide

Everything needed to ship the Signosoft Mobile SDK in a production iOS or iPadOS
app. If you are starting cold, read [GETTING-STARTED.md](GETTING-STARTED.md)
first.

---

## 1. Requirements

| | Minimum | Notes |
|---|---|---|
| iOS / iPadOS | **16.0** | the SDK uses `WKUIDelegate` media-capture APIs introduced in 15/16 without availability guards |
| Flutter | **3.44** | the plugin resolves its iOS side through Swift Package Manager, on by default from 3.44 |
| Dart | **3.12** | sealed classes and pattern matching |
| Xcode | 15 or newer | Swift tools 5.9 |

These floors are what the package needs. It has been **built and exercised only
on Flutter 3.44.8 / Dart 3.12.2 / Xcode 26.6**; lower versions inside the stated
ranges are untested.

**Android is not supported**, and **CocoaPods is not supported.** Both are
explained in [Known limitations](#known-limitations) — the reasons matter, so
read them before designing around either.

---

## 2. Host `Info.plist`

The SDK cannot declare usage strings on your behalf — iOS attributes them to the
host app. Without them, the matching signature methods fail silently inside the
WebView, or your app is terminated when the picker opens.

| Key | Needed for |
|---|---|
| `NSCameraUsageDescription` | photo / scan signature methods, identity verification |
| `NSMicrophoneUsageDescription` | identity verification that records video |
| `NSPhotoLibraryUsageDescription` | choosing an existing signature image |
| `NSLocalNetworkUsageDescription` | only when `baseUrl` is on your LAN (development) |

Write real sentences — App Review rejects placeholders.

```xml
<key>NSCameraUsageDescription</key>
<string>Used to capture your signature.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Used by signature methods that record video.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Used to attach an image of your signature.</string>
```

The SDK answers WebKit's media-capture request with `.prompt`, so iOS shows the
standard permission alert the first time a signature method needs the camera.

### App Transport Security

An `https://` `baseUrl` needs **no ATS changes** — this is the production case.

For local development against a plain-HTTP shell:

```xml
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsLocalNetworking</key><true/></dict>
```

That covers `localhost` and private IP ranges without opening arbitrary cleartext
loads. It does **not** cover an `http://` public hostname — ATS blocks those and
the SDK reports `loadFailed` with WebKit's "requires the use of a secure
connection" message.

---

## 3. Installing, and why both packages ship together

### The dependency line

```yaml
dependencies:
  signosoft_signer:
    git:
      url: git@github.com:signosoft/signosoft-mobile-sdk.git
      ref: v0.4.0-beta        # always a tag, never `main`
      path: signosoft_signer
```

The repository is private: you need a GitHub account with read access and an SSH
key on it, or an HTTPS URL carrying a personal access token. Ask Signosoft for
access. In CI, give the runner the same key — pub shells out to `git`, so
whatever `git clone` can reach, pub can reach.

Pub clones the **whole repository** into its cache, which is what makes this work:
the plugin's symlink to the sibling Swift core resolves inside the clone. A
dependency mechanism that fetched only `signosoft_signer/` would not.

Bumping a version means changing `ref` and running `flutter pub get`. Pub caches
by ref, so re-resolving a tag you already have costs nothing.

This is the only supported install route. There is no release archive; if you
cannot reach GitHub, ask Signosoft.

### Why both packages ship together

However you obtain it, the repository holds two directories that must remain
siblings:

```
signosoft-mobile-sdk/
  signosoft_signer/    Flutter plugin  ← your pubspec points here
  ios/                 Swift core
  examples/medicly/    reference host app
```

Inside the plugin, `ios/signosoft_signer/SignosoftSignerCore` is a **symlink to
`../../../ios`** — the sibling directory. That is deliberate: there is exactly
one copy of the Swift core on disk, and both the Flutter plugin and native iOS
consumers use it.

The symlink lives *inside* the plugin package because Flutter copies the whole
plugin package into `ios/Flutter/ephemeral/Packages/.packages/` before building,
and Swift Package Manager resolves relative dependency paths against that
relocated location. A dependency path that climbed out of the package root would
resolve into `ephemeral/` and fail.

Consequences for you:

- Keep the two directories together, at the same relative depth.
- Obtain the tree with a tool that preserves symlinks. Git stores them as mode
  `120000` and `git clone` restores them, so the `git:` dependency is safe;
  `git archive`, GitHub's "Download ZIP" and some GUI clients dereference the
  link and silently duplicate the Swift core.
- Do not vendor `signosoft_signer/` into your repo on its own.

Check the link survived:

```bash
ls -l signosoft-mobile-sdk/signosoft_signer/ios/signosoft_signer/SignosoftSignerCore
# -> ../../../ios          (and `cat .../SignosoftSignerCore/Package.swift` works)
```

---

## 4. The API

```dart
static Future<SignosoftSignResult> open({
  required String token,
  required Uri baseUrl,
  Duration loadTimeout = const Duration(seconds: 45),
  void Function(SignosoftDiagnostic diagnostic)? onDiagnostic,
});
```

- **`token`** — the `bioid` your backend obtained from `createDocLink`.
- **`baseUrl`** — origin serving the Signosoft signing shell. Required;
  `https://www.signosoft.com/mobilesdk/` unless Signosoft gave your tenant its
  own origin.
- **`loadTimeout`** — how long the shell may take to become interactive before
  the session gives up with `loadTimeout`. Without this a wrong `baseUrl` leaves
  a patient staring at a blank screen indefinitely.
- **`onDiagnostic`** — see [Diagnostics](#7-diagnostics).

Only one ceremony can be open at a time; a second concurrent `open()` resolves
immediately with `alreadyOpen` rather than stacking view controllers.

**On throwing.** `open()` resolves rather than throws. Anticipated failures come
back as `Failed` with a code; anything unanticipated — a platform-channel codec
error, a reply of an unexpected shape — is caught as a last resort and returned as
`Failed(SignosoftErrorCode.unknown, …)` with the underlying error in the message.
Nothing the SDK does propagates an exception into your `await`, so a
`try`/`catch` around the call is not required.

A callback you pass to `onDiagnostic` is also guarded: if it throws, the throw is
swallowed and the ceremony continues. Diagnostics are a debugging aid and cannot
affect the session.

---

## 5. The four outcomes

```dart
sealed class SignosoftSignResult
  ├── sealed class SignosoftOutcome     // shared document + signer metadata
  │     ├── Signed      (+ downloadUrl, signedPdfPath)
  │     └── Rejected
  ├── Cancelled
  └── Failed            (code, message)
```

`SignosoftOutcome` carries `result`, `document`, `documentToken`, `lang`,
`signaturesSigned`, `signaturesTotal`, `lastSignerFirstName`,
`lastSignerLastName`, `lastSignerEmail`.

| Outcome | Server state | What to do |
|---|---|---|
| `Signed` | signed and recorded | fetch the PDF with `documentToken`; attach to the patient record |
| `Rejected` | rejected — **terminal** | record the refusal; the `bioid` cannot be signed afterwards |
| `Cancelled` | **not necessarily unchanged** — see below | you may open the same `bioid` again, but re-read the document's state rather than assuming nothing was recorded |
| `Failed` | usually unchanged | branch on `code` |

### `Cancelled` does not guarantee the server is untouched

For a document whose fields are **all** still unsigned, `Cancelled` means exactly
what it says: nothing was recorded, and the same `bioid` may be opened again.

It does not mean that on a multi-field document. A signer can complete one field
and then close the ceremony with the **X**. The host receives `Cancelled` while
that signature is already recorded server-side — measured 2026-08-18: one field
of a two-field document was signed, the ceremony was closed, `Cancelled` was
delivered to the host, and `openDocLink` reported `sigsigned=true` for that
field.

So read `Cancelled` as *"no terminal outcome was reached"*, not as *"nothing
happened"*. Where the difference matters — billing, audit, or a retry that must
not double-sign — ask your backend for the document's signature state after a
`Cancelled` instead of assuming it is untouched.

### A partly-signed document cannot be finished from inside the ceremony

There is no *Finalize* action in the ceremony. The document menu offers Rename,
Attachment, Send to email, Validate, Audit Trail, Download, Search, Thumbnails
and Print — and nothing that completes a document whose remaining fields are
still unsigned. The only exit is closing it, which reports `Cancelled`.

This is **tenant configuration, not an SDK limitation**: the test tenant reports
`allowPartialFinalize: false`. If your flow needs a signer to be able to submit a
document with some fields left unsigned, ask Signosoft to enable partial
finalisation for your tenant. Otherwise design for every required field being
signed in one sitting.

### `SignosoftErrorCode`

Branch on the code. The message is written for developers and its wording will
change.

| Code | Meaning | Typical cause |
|---|---|---|
| `invalidToken` | no usable `bioid` was supplied | empty string reached `open()` |
| `invalidBaseUrl` | `baseUrl` could not be turned into a loadable URL | malformed URI |
| `loadFailed` | the shell could not be loaded | wrong host, closed port, DNS failure, ATS block, HTTP ≥ 400 |
| `loadTimeout` | reached but never became ready inside `loadTimeout` | host accepts connections but never responds |
| `sessionFailed` | shell loaded, session could not be established | expired, already-used or unknown `bioid` |
| `alreadyOpen` | a ceremony is already on screen | double tap |
| `noPresenter` | no view controller to present from | called before the UI existed |
| `unsupportedPlatform` | not iOS | Android / web build |
| `notRegistered` | plugin missing from the build | dependency added without rebuilding iOS |
| `unknown` | anything else, including codes from a newer SDK | — |

---

## 6. Getting the signed PDF

**The supported route:** on `Signed`, send `documentToken` to your own backend,
which calls the Signosoft `downloadDoc` API (or `downloadContract` for
multi-document envelopes) with your credentials, and files the PDF.

`documentToken` is an identifier. It is **not** a download link — never put it in
a URL and never show it to a user.

**The convenience route:** `signedPdfPath` is the finished PDF written into your
app's temporary directory, so you can attach it to a chart immediately.

1. **It is best-effort.** Null when the fetch failed or the document exceeded the
   size ceiling. A null path never means the signature failed.
2. **It is temporary.** Copy it somewhere durable before relying on it; iOS may
   reclaim the temp directory.
3. **There is a 32 MB ceiling** on the decoded document. Above it the signature
   still succeeds and `signedPdfPath` is null. The bytes cross the JS→native
   bridge inside a single message; measured on an iPad Pro 13", a 50 MB document
   was delivered intact in about a second, so the ceiling is a memory guard on
   our side rather than a bridge limit.

`downloadUrl` is modelled end to end and is **always null today** — no backend
design has been chosen for minting one. There is no `downloadSignedPdf()` helper
in this version.

---

## 7. Diagnostics

`onDiagnostic` receives every bridge message the signing shell emits. It exists
to debug an integration — event names, payload shapes and ordering are **not
API** and may change in any release. Never branch product behaviour on them.

```dart
await SignosoftSigner.open(
  token: bioid,
  baseUrl: shell,
  onDiagnostic: (d) => log('signosoft: ${d.event} ${d.data ?? ''}'),
);
```

Typical output for a successful ceremony:

```
signosoft: ready {}
signosoft: signed {documentToken: contr-…, signaturesSigned: 2.0,
                   signaturesTotal: 2.0, pdfBase64Length: 1739416, …}
```

The signed PDF bytes are replaced by `pdfBase64Length`, so diagnostics stay
cheap to log. Native hosts get the same tap via
`SignosoftSignerViewController.onEvent`.

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Blank white screen, nothing happens | `baseUrl` reachable but not a signing shell, or the page never became interactive | wait for `loadTimeout` — you will get `loadTimeout`. Check `baseUrl` points at the **root** of the shell |
| `loadFailed`, "answered HTTP 500" | `baseUrl` points at a misconfigured or wrong host | verify the URL in a browser; `<host>/?bioid=<token>` must render the ceremony |
| `loadFailed`, "requires the use of a secure connection" | ATS blocked a cleartext load to a non-local host | use `https://`, or `NSAllowsLocalNetworking` for local development only |
| The ceremony renders, but signing fails with `crypto.subtle is undefined` | `baseUrl` is plain HTTP to an IP or hostname, so the page is not a *secure context* and WebCrypto does not exist. The shell needs it to encrypt biometric data | serve the shell over **HTTPS**. `localhost` counts as secure (simulators), a private IP over `http://` does not — it loads but can never complete a signature |
| `loadFailed`, "Could not connect to the server" | nothing listening on that host/port | check the shell is running and reachable **from the device**, not just the Mac |
| `sessionFailed`, "The document link is invalid" | the `bioid` is expired, already used, or unknown | mint a fresh token. Each token allows one terminal outcome |
| A **handwritten (signature-pad)** field shows **"Connection error."** and *Confirm Signature* never enables | the signature-pad driver is licensed per origin, and `https://www.signosoft.com` is not on the licence's origin allowlist, so the driver refuses to initialise. Server-side licence configuration — **not** the SDK, the WebView or the device: it reproduces in a desktop browser at the same origin, and the same document signs from an allowlisted origin | use a **typed** signature field and its *Draw* tab, which takes a finger-drawn signature and completes normally. To use pad fields, ask Signosoft to add your `baseUrl` origin to the licence allowlist, or to serve the shell from an origin already on it — `baseUrl` is an `open()` argument, so neither needs a code change on your side |
| `notRegistered` | plugin not in the iOS build | `flutter clean && flutter pub get`, then rebuild the iOS app |
| Camera prompt never appears | usage-description key missing from the **host** app's `Info.plist` | add `NSCameraUsageDescription` and rebuild |
| `Signed` but `signedPdfPath` is null | fetch failed, or the document is over 32 MB | expected — fetch server-side with `documentToken` |
| Signature completes but no result arrives | the tenant's completion redirect is disabled server-side | contact Signosoft; this is a tenant configuration issue, not a client bug |
| Some fields are signed, the rest are not, and there is no way to finish | the ceremony has no *Finalize* action, and the tenant reports `allowPartialFinalize: false` | tenant configuration, not the SDK — ask Signosoft to enable partial finalisation. Until then the only exit is closing the ceremony, which reports `Cancelled` even though the signatures already taken are recorded |
| Second tap does nothing | concurrency guard | expected — you get `alreadyOpen` |
| On a physical device: "Untrusted Developer", and the run hangs at *Installing and launching* | the signing certificate is not trusted on that device — nothing to do with the SDK | on the device: Settings → General → VPN & Device Management → *Developer App* → your `Apple Development: …` identity → **Trust**, then rerun. If that section is missing, enable Settings → Privacy & Security → **Developer Mode**, reboot, confirm |

---

## 9. Privacy and App Store submission

The SDK ships a `PrivacyInfo.xcprivacy` in both its targets, declaring:

- no tracking, no tracking domains
- no required-reason API usage
- collected data: name, email address, photos/videos and other user content —
  all linked to the user, none used for tracking, all for **App Functionality**

Those reflect what flows through the signing ceremony. Your own app's privacy
manifest and App Store answers must cover whatever *you* collect in addition.

---

## How this is tested

Five suites. The first three run in CI on every push to `main` and `dev`
(`.github/workflows/ci.yml`); the two example apps' suites are run locally and are
not gated, because the examples are not shipped as part of the package.

| Suite | Command | Tests | In CI | What it covers |
|---|---|---|---|---|
| Swift core, macOS | `swift test` in `ios/` | 14 | yes | bridge-message decoding, `SignedInfo` field mapping, the signed-PDF store (size ceiling, path-escape, bad input) |
| Swift, iOS Simulator | `xcodebuild test -scheme SignosoftSigner -destination "platform=iOS Simulator,id=<udid>"` in `ios/` | 35 (the 14 above **plus 21** simulator-only) | yes | the view-controller layer: WebView setup, bridge dispatch, the load-timeout watchdog, the HTTP-error path, teardown reporting `Cancelled`, and that signed-PDF bytes never reach the diagnostic tap |
| Dart plugin | `flutter analyze && flutter test` in `signosoft_signer/` | 22 | yes | the public API and the method-channel wire format: every outcome, every error code, empty token, null reply, non-iOS platform, diagnostics, and that `open()` returns rather than throws |
| Demo host app | `flutter test` in `examples/medicly/` | 6 | no | the reference app lays out with no overflow and keeps the Sign button reachable at phone and tablet widths |
| Bare example | `flutter test` in `signosoft_signer/example/` | 5 | no | the minimal host: all four outcomes render, and Sign stays disabled without a token |

The 21 simulator tests matter for judging maturity: everything behind
`#if canImport(UIKit)` — the WKWebView, the bridge, the watchdog, the HTTP-error
path — is compiled out on macOS, so before that suite existed CI's only check on
the WebView layer was that it compiled. A simulator destination is the only one
that both compiles and executes it.

CI also asserts that the Swift core is still reachable through the symlink (see
[§3](#3-installing-and-why-both-packages-ship-together)), and builds
`examples/medicly` for the simulator on pull requests — the one check that
exercises the plugin, the symlink and Swift Package Manager the way your build
will.

A green suite is not the same as an end-to-end signature. What has and has not
been exercised against the live service is below.

---

## Known limitations

Verified as working:

- `Signed` end to end with **typed** signature fields, including a genuinely
  signed PDF (two `/ByteRange` entries, `ETSI.CAdES.detached`), from a clean-room
  app that consumed the SDK as a dependency
- `Cancelled`, `alreadyOpen`, `invalidToken`, `sessionFailed`, `loadFailed`
  (closed port, HTTP 500, ATS block), `loadTimeout`
- documents up to 50 MB across the bridge; 32 MB delivered as a local file
- the SwiftUI `SignosoftSignerSheet` wrapper

Known broken, cause identified, fix is not in this repository:

- **Handwritten (signature-pad) fields cannot be completed** from
  `https://www.signosoft.com/mobilesdk/`. The field opens, the pad renders
  *"Connection error."*, and *Confirm Signature* stays disabled. The pad's driver
  is licensed against an origin allowlist and that origin is not on it, so the
  driver refuses to initialise. This is licence configuration on the server side:
  it reproduces in a plain desktop browser at the same origin, and the same
  document, token and field drive a live pad from an allowlisted origin — so it is
  not the SDK, WKWebView, the simulator or the device. **A typed signature field
  works, including its *Draw* tab, which captures a finger-drawn signature.** Two
  remedies, both outside the SDK and both needing no code change from you: have
  the origin added to the licence allowlist, or point `baseUrl` at an origin
  already on it. Talk to Signosoft about which. Note that a completed *pad*
  signature has not itself been observed end to end — the pad accepts ink and
  enables *Confirm* on an allowlisted origin, but no such ceremony has been
  confirmed through to a stamped PDF.

Not verified — treat as unknown, not as working:

- **`Rejected` end to end.** Implemented and unit-tested on all three layers, but
  never exercised against a live rejection: the *Reject* control is not rendered
  for the test tenant, which is a server-side button configuration.
- **Physical hardware.** Everything in the verified list above was run on the iOS
  Simulator: the signature ceremony on the iPad Pro 13" simulator, and the demo
  host app on the iPhone 17 simulator as well. **No run on a physical iPhone or
  iPad has happened yet** — a device test is planned, not done. Nothing in the SDK is
  simulator-specific, but treat device behaviour as unverified until it is. The
  device-side setup steps in
  [examples/medicly/README.md](../examples/medicly/README.md#running-on-a-physical-iphone-or-ipad)
  are there for when you try it, and are not a claim that we have.
- **Camera-based signature methods**, and the media-permission prompt. They
  cannot run on the Simulator at all.
- **Interruption handling** — backgrounding mid-ceremony, rotation, incoming
  calls. A WebView content-process crash is handled (`loadFailed`); the rest is
  untested.
- **Session expiry** while the ceremony sits open past the token's lifetime.

Not supported:

- **Android.** There is no Android implementation in this release. The plugin
  declares iOS only, and on an Android build `open()` resolves to
  `Failed(unsupportedPlatform)` — it does not throw, and nothing is presented.
  Plan an Android app around a different route, or ask Signosoft about the
  roadmap; do not plan around this package.
- **CocoaPods.** The podspec was removed in this release: CocoaPods discards
  source files whose real path escapes the pod root, so the shared Swift core
  could never be compiled into the pod. It had never successfully built. Use
  Flutter 3.44+ with Swift Package Manager.
- **Bank iD and other external identity-provider hop-outs.**
- **`downloadUrl`** — modelled, always null (see §6).
