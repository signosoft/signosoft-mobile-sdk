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

Depend on the repository and point `path` at the plugin inside it. Pub clones the
whole repository, so the Swift core next door resolves:

```yaml
# pubspec.yaml
dependencies:
  signosoft_signer:
    git:
      url: git@github.com:signosoft/signosoft-mobile-sdk.git
      ref: v0.4.0-beta
      path: signosoft_signer
```

```bash
flutter pub get
```

The repository is private — you need a GitHub account with read access and an SSH
key on it. Ask Signosoft. For an HTTPS checkout instead, use
`https://<token>@github.com/signosoft/signosoft-mobile-sdk.git`; never commit that
URL with the token in it.

**Always pin `ref` to a tag.** Tracking `main` means your build changes without
you asking it to. The exact tag to pin is fixed at release — take it from the
release note Signosoft sends with your access, not from this snippet.

Your app needs an **iOS 16.0** deployment target and a few `Info.plist` keys —
both covered in [docs/INTEGRATION.md](docs/INTEGRATION.md).

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
  case Cancelled():
    // Closed without finishing. Nothing changed; you may open it again.
  case Failed(:final code, :final message):
    // Branch on `code`; `message` is for developers, not patients.
}
```

`open()` resolves instead of throwing: every failure the SDK anticipates arrives
as `Failed` with a `SignosoftErrorCode`. It is not an absolute guarantee — only
`PlatformException` and `MissingPluginException` are translated, so an
unexpected platform-channel error can still surface as a thrown exception. If a
throw would be fatal to your flow, wrap the call. See
[docs/INTEGRATION.md](docs/INTEGRATION.md#4-the-api).

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

An **alpha** for a named pilot. Use requires a paid commercial agreement with
Signosoft and an active service account; see `LICENSE`. Not licensed for
redistribution.

**`baseUrl` is `https://www.signosoft.com/mobilesdk/`** — the hosted signing
shell. Pass it as-is unless Signosoft has given your tenant a different origin.

Every push runs the full suite on a macOS runner: the Swift core on macOS, the
WebView layer on an iOS Simulator destination via `xcodebuild test`, and the Dart
plugin (`flutter analyze`, `dart format --set-exit-if-changed`, `flutter test`).
Counts and what each one covers are in
[docs/INTEGRATION.md](docs/INTEGRATION.md#how-this-is-tested).

[Known limitations](docs/INTEGRATION.md#known-limitations) lists honestly what is
verified and what is not — read it before you plan around a signature method.
One thing to know up front: the **handwritten (signature-pad) field cannot be
completed** from the hosted shell's origin today. The typed field's *Draw* tab
gives you a finger-drawn signature that does work.

Bugs and questions: **info@signosoft.com**. Include the `SignosoftErrorCode`,
the `documentToken` if you have one, and the diagnostic log described in the
integration guide.
