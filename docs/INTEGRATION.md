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

**CocoaPods is not supported.** See
[Known limitations](#known-limitations).

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
      ref: v0.3.0-alpha        # always a tag, never `main`
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
- **`baseUrl`** — origin serving the Signosoft signing shell. Required; ask
  Signosoft for yours.
- **`loadTimeout`** — how long the shell may take to become interactive before
  the session gives up with `loadTimeout`. Without this a wrong `baseUrl` leaves
  a patient staring at a blank screen indefinitely.
- **`onDiagnostic`** — see [Diagnostics](#7-diagnostics).

Only one ceremony can be open at a time; a second concurrent `open()` resolves
immediately with `alreadyOpen` rather than stacking view controllers.

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
| `Cancelled` | unchanged | you may open the same `bioid` again |
| `Failed` | usually unchanged | branch on `code` |

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
| `loadFailed`, "Could not connect to the server" | nothing listening on that host/port | check the shell is running and reachable **from the device**, not just the Mac |
| `sessionFailed`, "The document link is invalid" | the `bioid` is expired, already used, or unknown | mint a fresh token. Each token allows one terminal outcome |
| `notRegistered` | plugin not in the iOS build | `flutter clean && flutter pub get`, then rebuild the iOS app |
| Camera prompt never appears | usage-description key missing from the **host** app's `Info.plist` | add `NSCameraUsageDescription` and rebuild |
| `Signed` but `signedPdfPath` is null | fetch failed, or the document is over 32 MB | expected — fetch server-side with `documentToken` |
| Signature completes but no result arrives | the tenant's completion redirect is disabled server-side | contact Signosoft; this is a tenant configuration issue, not a client bug |
| Second tap does nothing | concurrency guard | expected — you get `alreadyOpen` |

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

## Known limitations

Verified as working:

- `Signed` end to end, including a genuinely signed PDF (two `/ByteRange`
  entries, `ETSI.CAdES.detached`), from a clean-room app that consumed the SDK
  as a dependency
- `Cancelled`, `alreadyOpen`, `invalidToken`, `sessionFailed`, `loadFailed`
  (closed port, HTTP 500, ATS block), `loadTimeout`
- documents up to 50 MB across the bridge; 32 MB delivered as a local file
- the SwiftUI `SignosoftSignerSheet` wrapper

Not verified — treat as unknown, not as working:

- **`Rejected` end to end.** Implemented and unit-tested on all three layers, but
  never exercised against a live rejection: the *Reject* control is not rendered
  for the test tenant, which is a server-side button configuration.
- **Physical hardware.** Everything above was run on the iPad Pro 13" simulator.
- **Camera-based signature methods**, and the media-permission prompt. They
  cannot run on the Simulator at all.
- **Interruption handling** — backgrounding mid-ceremony, rotation, incoming
  calls. A WebView content-process crash is handled (`loadFailed`); the rest is
  untested.
- **Session expiry** while the ceremony sits open past the token's lifetime.

Not supported:

- **Android.** `open()` returns `unsupportedPlatform`.
- **CocoaPods.** The podspec was removed in this release: CocoaPods discards
  source files whose real path escapes the pod root, so the shared Swift core
  could never be compiled into the pod. It had never successfully built. Use
  Flutter 3.44+ with Swift Package Manager.
- **Bank iD and other external identity-provider hop-outs.**
- **`downloadUrl`** — modelled, always null (see §6).
