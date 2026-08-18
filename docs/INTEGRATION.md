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

### Setting the deployment target

The floor is stated everywhere and met nowhere by default: a project created with
`flutter create` on 3.44.8 carries `IPHONEOS_DEPLOYMENT_TARGET = 13.0` in **three**
build configurations — Debug, Release and Profile — and all three need raising.

```bash
grep -c IPHONEOS_DEPLOYMENT_TARGET ios/Runner.xcodeproj/project.pbxproj
# 3
```

Set it once in Xcode under **Runner → General → Minimum Deployments**, which
rewrites all three, or edit the three lines in
`ios/Runner.xcodeproj/project.pbxproj` directly. Leaving one behind builds until
the linker reaches the SDK.

There is **no `Podfile` to change.** With Swift Package Manager on by default from
Flutter 3.44, `flutter create` emits none, so the `platform :ios, '16.0'` advice
you will find by searching does not apply to this project — see
[CocoaPods under Known limitations](#known-limitations).

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
| `NSLocalNetworkUsageDescription` | only for a locally served development shell (see App Transport Security below) |

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

An `https://` `baseUrl` needs **no ATS changes** — this is the production case,
and now very nearly the only case.

`baseUrl` is validated before anything is loaded: it must be an `https://` origin
with a host, and plain `http://` is accepted only for `localhost`, `*.localhost`,
`127.0.0.1`, `::1` and `10.0.2.2`. The only cleartext shell the SDK will open at
all is therefore one served on the machine running the simulator, and that is what
this exception is for:

```xml
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsLocalNetworking</key><true/></dict>
```

It no longer buys you a LAN IP. `http://192.168.x.x` is rejected up front with
`invalidBaseUrl`, before the signer appears, rather than loading and failing later:
a cleartext page is not a *secure context*, so WebCrypto does not exist there and
the shell could never have completed a signature over it. To drive a
development shell from a physical device, put it behind `https://`.

---

## 3. Installing, and why both packages ship together

### The dependency line

```yaml
dependencies:
  signosoft_signer:
    git:
      url: https://github.com/signosoft/signosoft-mobile-sdk.git
      ref: v0.4.3-beta        # always a tag, never a branch
      path: signosoft_signer
```

The repository is **public over HTTPS**, so this needs no credentials: no GitHub
account, no SSH key, no personal access token, and nothing extra on a CI runner.
Pub shells out to `git`, so whatever `git clone` of that URL can reach, pub can
reach.

The `path:` key here belongs to the `git:` block and selects a subdirectory of the
clone. It is not pub's local `path:` dependency — see below for why the whole
repository has to come down.

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

Check the link survived. Installed as a `git:` dependency you have no directory
called `signosoft-mobile-sdk`: pub's clone lives in its cache under a
SHA-suffixed name, so glob for it.

```bash
ls -l ~/.pub-cache/git/signosoft-mobile-sdk-*/signosoft_signer/ios/signosoft_signer/SignosoftSignerCore
```

```
lrwxr-xr-x@ 1 you staff 12 Aug 18 10:35 /Users/you/.pub-cache/git/signosoft-mobile-sdk-b47384fe3b9200c13efc46f57b44f3d3b4117a13/signosoft_signer/ios/signosoft_signer/SignosoftSignerCore -> ../../../ios
```

`l` in the mode column and `-> ../../../ios` are what you want. That it also
resolves:

```bash
head -1 ~/.pub-cache/git/signosoft-mobile-sdk-*/signosoft_signer/ios/signosoft_signer/SignosoftSignerCore/Package.swift
# // swift-tools-version: 5.9
```

(With more than one ref cached, `head` prefixes each match with its own path.)

**The symlink does survive `flutter pub get`** — verified in the pub cache on
2026-08-18, across three cache entries from three different refs — and Xcode
resolves the Swift core through it, at the relocated path this section predicts:

```
SignosoftSigner: <your app>/ios/Flutter/ephemeral/Packages/.packages/signosoft_signer/SignosoftSignerCore @ local
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
  own origin. It must be an `https://` origin **with a host**. Plain `http://` is
  accepted only for `localhost`, `*.localhost`, `127.0.0.1`, `::1` and `10.0.2.2`
  while developing. Anything else resolves to `Failed(invalidBaseUrl)`
  immediately, before the signer appears — a public `http://` origin is rejected
  outright, and could not complete a signature anyway: it is not a secure
  context, so WebCrypto does not exist there. The check runs before the token is
  ever put on the wire. Native hosts can run it themselves with
  `SignosoftSigner.isUsableBaseURL(_:)`, which is public for that reason.
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

**An outcome with no `documentToken` is a failure, not a signature.** If the shell
announces a completed ceremony but supplies no `documentToken`, `open()` resolves
to `Failed(sessionFailed)` rather than `Signed`. Every other metadata field may
safely default — a malformed middle name must never lose a signature — but that
one may not: it is the only handle you have on the document, so a blank one would
send your backend to fetch nothing and report success. This has not been seen from
the live shell; it is a guard against a hollow success, not a described failure
mode.

---

## 4a. What the signer actually does

Worth knowing before you demo it, because nothing on screen explains it and a
signer who taps in the wrong place gets no feedback at all.

1. The document opens with each signature field marked **Click to sign**.
2. Tapping the field — and it has to be *on* the field; a tap a few points outside
   does nothing and says nothing — opens a sheet.
3. The sheet offers **Type**, **Draw** and **Image**. *Type* is pre-filled with the
   signer's name. **Draw** is the one that captures a finger-drawn signature, and
   it is what to use on a phone or tablet.
4. **done** applies it. The field is replaced by a stamp: the Signosoft frame,
   *Digitally signed by*, the mark, the name and the date.
5. When the last required field is signed the ceremony finalises itself and the
   SDK reports `Signed`. There is no separate submit button, and there is no way
   to finalise a document that still has unsigned required fields — see below.

A signature-pad field looks similar but says **Connect Signpad**, and cannot
currently be completed from the hosted origin. See
[Known limitations](#known-limitations).

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
| `Rejected` | rejected — **terminal** | record the refusal; the `bioid` cannot be signed afterwards. Whether a *Reject* control is rendered at all is tenant configuration — see below |
| `Cancelled` | **not necessarily unchanged** — see below | you may open the same `bioid` again, but re-read the document's state rather than assuming nothing was recorded |
| `Failed` | usually unchanged | branch on `code` |

### `Rejected` is wired through, and has never been exercised end to end

Rejection is a real product feature, not a placeholder. It is in the signing
shell's own bridge contract alongside `signed`, `cancelled` and `error`; the
Signosoft REST API has a `reject` endpoint with its own error taxonomy; and all
three layers of this SDK handle it — the Swift bridge maps the `rejected` event,
the plugin marshals it, and Dart delivers a `Rejected` with the same document and
signer metadata `Signed` carries. It is unit-tested on every layer.

What has never happened is a live rejection. **Our test tenant renders no *Reject*
control** — it reports `showPRReject: false` — so no ceremony has ever emitted the
event against the real service. Treat the branch as implemented and unproven.

Two consequences for you:

- **Ask Signosoft whether Reject is enabled for your tenant.** It is a server-side
  button configuration, not something the SDK can turn on.
- **Handle the branch regardless.** `SignosoftSignResult` is `sealed`, so your
  `switch` will not compile without it — which is the point. If a tenant with
  Reject enabled sends the event and nothing handles it, the signer sits there
  until the 45-second watchdog gives up. Handling it costs you three lines.

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

### An already-signed `bioid` still opens, and closing it reports `Cancelled`

A token whose signature has already **completed** is not rejected. Opening it
again renders the finished document, read-only, with its signature block on it;
diagnostics show `ready` and no `error` event at all. Closing it delivers
`Cancelled`.

Measured 2026-08-18: a one-field document was signed to completion and `Signed`
was delivered with a `documentToken`; the same `bioid`, unchanged, was then opened
again, rendered the signed document, and reported `Cancelled` when closed.

So a consumed token does not start failing, and `sessionFailed` is **not** what
you get for one — see the error table below for what it does mean. Never use the
outcome of `open()` to decide whether a token is still usable: ask your backend
for the document's signature state.

This is a different case from the one immediately below, where fields remain
unsigned and cannot be completed. Here there is nothing left to sign.

### A partly-signed document cannot be finished from inside the ceremony

There is no *Finalize* action in the ceremony. The document menu offers Rename,
Attachment, Send to email, Validate, Audit Trail, Download, Search, Thumbnails
and Print — and nothing that completes a document whose remaining fields are
still unsigned. The only exit is closing it, which reports `Cancelled`.

The test tenant reports `allowPartialFinalize: false`, and whether partial
finalisation is enabled for your tenant is a question for Signosoft.

That flag is **not** why a multi-field document stalls. The cause is that **one
`bioid` covers one document**, and this release is built around a single signature field per document, so this case does not arise when
with that token in the first place — no *Finalize* button would have helped. Mint
a document with a single signature field and this case does not arise; see
[GETTING-STARTED.md](GETTING-STARTED.md#one-bioid-per-document) for
the constraint and for how well it is established.

### `SignosoftErrorCode`

Branch on the code. The message is written for developers and its wording will
change.

| Code | Meaning | Typical cause |
|---|---|---|
| `invalidToken` | no usable `bioid` was supplied | empty string reached `open()` |
| `invalidBaseUrl` | `baseUrl` is not an origin the signer will load | a malformed or scheme-less URI, no host, or a plain-`http://` origin that is not loopback. Checked before anything loads |
| `loadFailed` | the shell could not be loaded | wrong host, DNS failure, ATS block, HTTP ≥ 400. A refused connection is not one of these — it ends as `loadTimeout` |
| `loadTimeout` | reached but never became ready inside `loadTimeout` | host accepts connections but never responds |
| `sessionFailed` | shell loaded, session could not be established | the `bioid` is unknown or malformed — the server reports `DOC_LINK_NOT_EXIST` — or expired. Also reported if the shell announces an outcome carrying no `documentToken`. **Not** what a token whose signature already completed gives you: that opens, and closing it reports `Cancelled` |
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
signosoft: signed {documentToken: contr-…, signaturesSigned: 1.0,
                   signaturesTotal: 1.0, pdfBase64Length: 1201788, …}
```

The signed PDF bytes are replaced by `pdfBase64Length`, so diagnostics stay
cheap to log. Native hosts get the same tap via
`SignosoftSignerViewController.onEvent`.

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `flutter build ios` fails with `Exited with status code 255` and nothing else | the project sits under an iCloud-synced directory (`~/Desktop`, `~/Documents`), so build output acquires file-provider extended attributes and `codesign` refuses the Flutter framework. Re-run with `-v`: the real message is *"resource fork, Finder information, or similar detritus not allowed"*, which the plain output never shows | keep build output outside the synced tree: `rm -rf build && mkdir -p ~/.flutter-build/<app> && ln -s ~/.flutter-build/<app> build`. Or move the project to a path iCloud does not manage. Renaming the directory `.nosync` is **not** enough — that stops the upload, not the extended attributes, and `xattr -l` on such a directory still lists `com.apple.fileprovider.dir#N`. Flutter already tries `xattr -r -d` itself and still fails, because the file provider re-applies them |
| Blank white screen, nothing happens | `baseUrl` reachable but not a signing shell, or the page never became interactive | wait for `loadTimeout` — you will get `loadTimeout`. Check `baseUrl` points at the **root** of the shell |
| `loadFailed`, "answered HTTP 500" | `baseUrl` points at a misconfigured or wrong host | verify the URL in a browser; `<host>/?bioid=<token>` must render the ceremony |
| `loadFailed`, "requires the use of a secure connection" | ATS blocked a cleartext load to a non-local host | use `https://`, or `NSAllowsLocalNetworking` for local development only |
| `invalidBaseUrl`, before the signer ever appears | `baseUrl` is not an `https://` origin with a host: a typo, a scheme-less string, or a plain-`http://` origin that is not loopback | use `https://`. Plain `http://` is accepted only for `localhost`, `*.localhost`, `127.0.0.1`, `::1` and `10.0.2.2`. The reason it is refused rather than attempted: a cleartext page is not a *secure context*, so WebCrypto does not exist there and the shell — which needs it to encrypt biometric data — could never complete a signature. Earlier releases loaded such an origin and failed later with `crypto.subtle is undefined` |
| `loadTimeout` after a blank screen for the whole timeout | nothing is listening on that host and port, or something accepts the connection and never serves the shell. A refused connection is **not** reported as `loadFailed` — WebKit does not hand us a failure for it, so the watchdog is what ends the wait | check the shell is running and reachable **from the device**, not just from the Mac. Measured on 2026-08-18 against a closed port on loopback: 45 s of spinner, then `loadTimeout` |
| `sessionFailed`, "The document link is invalid" | the `bioid` is unknown or malformed, or expired — the server reports `DOC_LINK_NOT_EXIST` | mint a fresh token. Note this is **not** the already-signed case: a token whose signature completed opens normally and reports `Cancelled` when closed |
| `sessionFailed` / `DOC_LINK_NOT_EXIST` on a token you are sure is good, on a simulator you have run this app on before | stale WebKit storage from an earlier install made the shell resolve an empty `docLink`, and the server answers that with the same reason code it uses for a dead token — indistinguishable from the outside, which is what makes it expensive | `xcrun simctl uninstall <udid> <your bundle id>` and run again; reinstalling over the top does not clear it. Observed before each ceremony was given its own non-persistent WebView store, which should remove the cause — that has not been re-tested, so the uninstall is still the cheap first check |
| A **handwritten (signature-pad)** field shows **"Connection error."** and *Confirm Signature* never enables | the signature-pad driver is licensed per origin, and `https://www.signosoft.com` is not on the licence's origin allowlist, so the driver refuses to initialise. Server-side licence configuration — **not** the SDK, the WebView or the device: it reproduces in a desktop browser at the same origin, and the same document signs from an allowlisted origin | use a **typed** signature field and its *Draw* tab, which takes a finger-drawn signature and completes normally. To use pad fields, ask Signosoft to add your `baseUrl` origin to the licence allowlist, or to serve the shell from an origin already on it — `baseUrl` is an `open()` argument, so neither needs a code change on your side |
| `notRegistered` | plugin not in the iOS build | `flutter clean && flutter pub get`, then rebuild the iOS app |
| Camera prompt never appears | usage-description key missing from the **host** app's `Info.plist` | add `NSCameraUsageDescription` and rebuild |
| `Signed` but `signedPdfPath` is null | fetch failed, or the document is over 32 MB | expected — fetch server-side with `documentToken` |
| Signature completes but no result arrives | the tenant's completion redirect is disabled server-side | contact Signosoft; this is a tenant configuration issue, not a client bug |
| Some fields are signed, the rest are not, and there is no way to finish | the ceremony has no *Finalize* action, and the test tenant reports `allowPartialFinalize: false` | give each document a single signature field ([why](GETTING-STARTED.md#one-bioid-per-document)). The only exit from a part-signed document is closing the ceremony, which reports `Cancelled` even though the signature already taken is recorded |
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
| Swift core, macOS | `swift test` in `ios/` | 21, of which **1 skipped** | yes | bridge-message decoding, `SignedInfo` field mapping, `baseUrl` origin validation, the signed-PDF store (size ceiling, path-escape, bad input) |
| Swift, iOS Simulator | `xcodebuild test -scheme SignosoftSigner -destination "platform=iOS Simulator,id=<udid>"` in `ios/` | 51, of which **1 skipped** (the 21 above **plus 30** simulator-only) | yes | the view-controller layer: WebView setup, bridge dispatch, the load-timeout watchdog, the HTTP-error path, `invalidBaseUrl` rejection before load, teardown reporting `Cancelled`, that signed-PDF bytes never reach the diagnostic tap, and that no error message carries the `bioid` |
| Dart plugin | `flutter analyze && flutter test` in `signosoft_signer/` | 22 | yes | the public API and the method-channel wire format: every outcome, every error code, empty token, null reply, non-iOS platform, diagnostics, and that `open()` returns rather than throws |
| Demo host app | `flutter test` in `examples/medicly/` | 6 | no | the reference app lays out with no overflow and keeps the Sign button reachable at phone and tablet widths |
| Bare example | `flutter test` in `signosoft_signer/example/` | 5 | no | the minimal host: all four outcomes render, and Sign stays disabled without a token |

Counts measured on 2026-08-18. CI additionally runs `dart format
--set-exit-if-changed` over the plugin.

**The one skipped test is the same test in both Swift suites**, and it is skipped
for an honest reason rather than a broken one: it asserts that the signed PDF is
written with **complete file protection**, so it cannot be read while the device is
locked. macOS has no such API, and the Simulator's filesystem reports no
protection class at all, so neither destination can observe the attribute. **Only a
run on physical hardware can prove that one** — and no device run has happened
yet (see [Known limitations](#known-limitations)). The protection is applied in the
write itself, not conditionally, so it is present on a device; it is the
*assertion* that cannot execute anywhere we run today.

The 28 simulator-only tests matter for judging maturity: everything behind
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

- `Signed` end to end with a **typed** signature field, including a genuinely
  signed PDF (a `/ByteRange` array covering two ranges, `ETSI.CAdES.detached`), from a clean-room
  app that consumed the SDK as a `git:` dependency, on a document with a single
  signature field
- `Cancelled`, `alreadyOpen`, `invalidToken`, `sessionFailed`, `loadFailed`
  (HTTP ≥ 400, ATS block), `loadTimeout`. A **closed port** is not in this
  list: it produces `loadTimeout`, not `loadFailed` — see the troubleshooting table
- documents up to 50 MB across the bridge; 32 MB delivered as a local file
- the SwiftUI `SignosoftSignerSheet` wrapper
- that the Swift core's symlink survives `flutter pub get` and that Xcode resolves
  through it in a consumer's own app — checked in the pub cache, 2026-08-18

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

Established, and worth planning around rather than discovering:

- **An already-signed `bioid` still opens** and reports `Cancelled` when closed,
  rather than `sessionFailed` (see [§5](#5-the-four-outcomes)).

Not verified — treat as unknown, not as working:

- **`Rejected` end to end.** Rejection is a real product feature — it is in the
  signing shell's own bridge contract next to `signed` and `cancelled`, and the
  REST API has a `reject` endpoint with its own error taxonomy. It is implemented
  and unit-tested on all three layers of this SDK. What has not happened is a live
  rejection: our test tenant renders no *Reject* control (`showPRReject: false`),
  which is server-side button configuration. **Ask Signosoft whether Reject is
  enabled for your tenant, and handle the branch either way** — the sealed result
  type makes that mandatory, and an unhandled `rejected` event would leave the
  signer waiting out the 45-second watchdog. See
  [§5](#5-the-four-outcomes).
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
