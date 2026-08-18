# Signosoft Mobile SDK

Open the Signosoft signature ceremony **inside** your app and get a typed result
back. The patient never leaves your UI and never sees a browser.

**iOS and iPadOS only in this phase. There is no Android support** — on Android
`open()` returns `unsupportedPlatform` and nothing is presented. See
[Known limitations](docs/INTEGRATION.md#known-limitations).

```
Your Flutter app
      │
      │  SignosoftSigner.open(token: bioid, baseUrl: shell)
      ▼
signosoft_signer   Flutter plugin (Dart API)
      │
SignosoftSigner    Swift core (SwiftPM, hosts a WKWebView)
      │
      ▼
Signosoft signing shell  ──►  Signosoft REST API
```

## What's in this repository

| Directory | What it is | Who consumes it |
|---|---|---|
| `signosoft_signer/` | Flutter plugin — the Dart API | Flutter apps |
| `ios/` | Swift core — `SignosoftSigner`, a SwiftPM package | native iOS apps |
| `examples/medicly/` | reference host app — patient view, PDF, Sign button; runs on iPhone and iPad | you, first |
| `docs/` | getting started, and the full integration guide | you, first |

**Both directories must stay side by side.** The plugin reaches the Swift core
through a relative symlink; moving or splitting them breaks the build. See
[docs/INTEGRATION.md](docs/INTEGRATION.md#why-both-packages-ship-together).

## Install

Depend on the repository with a `git:` dependency, and use the `git:` block's own
`path:` key to select the plugin subdirectory inside it — that is not pub's local
`path:` dependency. Pub clones the whole repository, so the Swift core next door
resolves:

```yaml
# pubspec.yaml
dependencies:
  signosoft_signer:
    git:
      url: https://github.com/signosoft/signosoft-mobile-sdk.git
      ref: v0.4.0-beta
      path: signosoft_signer
```

```bash
flutter pub get
```

The repository is public over HTTPS. `flutter pub get` needs no credentials — no
GitHub account, no SSH key, no personal access token — on a developer machine or
on a CI runner.

**Always pin `ref` to a tag.** `v0.4.0-beta` is this release. Tracking a branch
means your build changes without you asking it to; if Signosoft's release note
names a newer tag, pin that one instead.

Your app needs an **iOS 16.0** deployment target and a few `Info.plist` keys —
both covered in [docs/INTEGRATION.md](docs/INTEGRATION.md), including where to
change the deployment target in a Flutter project that has no `Podfile`.

Native iOS apps add `ios/` as a local Swift package and `import SignosoftSigner`.

## Use it

```dart
import 'package:signosoft_signer/signosoft_signer.dart';

final result = await SignosoftSigner.open(
  token: bioid,                            // your backend minted this
  baseUrl: Uri.parse('https://www.signosoft.com/mobilesdk/'),
);

switch (result) {
  case Signed(:final documentToken, :final signedPdfPath):
    // Signed and recorded. Fetch the PDF server-side with documentToken;
    // signedPdfPath is a local convenience copy and may be null.
  case Rejected(:final documentToken):
    // The signer refused. Terminal — this bioid cannot be signed afterwards.
    // Whether a Reject control is offered at all is tenant configuration; the
    // branch is still mandatory, which is the point of the type being sealed.
  case Cancelled():
    // No terminal outcome was reached. Not a promise that nothing was recorded
    // — re-read the document's state from your backend.
  case Failed(:final code, :final message):
    // Branch on `code`; `message` is for developers, not patients.
}
```

`open()` resolves instead of throwing. Every failure the SDK anticipates arrives
as `Failed` with a `SignosoftErrorCode`, and anything unanticipated — a
platform-channel codec error, a reply of an unexpected shape — is caught as a
last resort and returned as `Failed(unknown, …)`. Nothing the SDK does
propagates an exception into your `await`, so a `try`/`catch` around the call is
not required. See [docs/INTEGRATION.md](docs/INTEGRATION.md#4-the-api).

Native Swift:

```swift
SignosoftSigner.present(from: self, token: bioid, baseURL: url) { result in
    switch result {
    case .signed(let info):   // info.documentToken, info.signedPdfFileURL, …
    case .rejected(let info):
    case .cancelled:
    case .error(let error):   // `as? SignosoftError` gives you a `.code`
    }
}
```

SwiftUI: `SignosoftSignerSheet` inside a `.fullScreenCover`. It deliberately
does **not** dismiss itself — the caller owns presentation state.

## Where the signed PDF comes from

Two routes, and you should design for the first:

1. **`documentToken` + your backend.** On `Signed`, hand `documentToken` to your
   own server, which calls the Signosoft `downloadDoc` API with your
   credentials. This is the supported route and the only one that works for
   documents of any size.
2. **`signedPdfPath`** — a copy the SDK writes into the app's temporary
   directory, for "attach to the chart right now". It is **null** when the
   document could not be fetched or exceeds 32 MB. A null path never means the
   signature failed.

`downloadUrl` exists on the result type and is **always null today** — the
backend does not mint one yet. Never show `documentToken` to a user or put it in
a URL: it is an identifier, not a link.

## Documentation

- [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) — one page for a developer
  picking this up cold: what a `bioid` is, who mints it, what you need from
  Signosoft.
- [docs/INTEGRATION.md](docs/INTEGRATION.md) — the full guide: install,
  `Info.plist`, App Transport Security, every outcome, troubleshooting, how the
  SDK is tested, known limitations.
- [examples/medicly/](examples/medicly/) — the reference host app, and the
  fastest way to see the whole flow working.
- `signosoft_signer/CHANGELOG.md`, `ios/CHANGELOG.md`.

## Status

A **beta** for a named pilot. Use requires a paid commercial agreement with
Signosoft and an active service account; see `LICENSE`. Not licensed for
redistribution.

**`baseUrl` is `https://www.signosoft.com/mobilesdk/`** — the hosted signing
shell. Pass it as-is unless Signosoft has given your tenant a different origin.

`baseUrl` must be an `https://` origin with a host. Plain `http://` is accepted
only for `localhost`, `*.localhost`, `127.0.0.1`, `::1` and `10.0.2.2` while
developing. Anything else returns `invalidBaseUrl` immediately, before the signer
appears — a public `http://` origin is rejected outright, and could not complete a
signature anyway: it is not a secure context, so WebCrypto does not exist there.

Every push runs the full suite on a macOS runner: the Swift core on macOS, the
WebView layer on an iOS Simulator destination via `xcodebuild test`, and the Dart
plugin (`flutter analyze`, `dart format --set-exit-if-changed`, `flutter test`).
Counts and what each one covers are in
[docs/INTEGRATION.md](docs/INTEGRATION.md#how-this-is-tested).

[Known limitations](docs/INTEGRATION.md#known-limitations) lists honestly what is
verified and what is not — read it before you plan around a signature method.
Two things to know up front. The **handwritten (signature-pad) field cannot be
completed** from the hosted shell's origin today; the typed field's *Draw* tab
gives you a finger-drawn signature that does work. And **one `bioid` authorises
one signature**, so a document with several signature fields needs one token and
one `open()` per field — see
[docs/GETTING-STARTED.md](docs/GETTING-STARTED.md#one-bioid-authorises-one-signature).

Bugs and questions: **info@signosoft.com**. Include the `SignosoftErrorCode`,
the `documentToken` if you have one, and the diagnostic log described in the
integration guide.
