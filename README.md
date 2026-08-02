# Signosoft Mobile SDK

Open the Signosoft signature ceremony **inside** your app and get a typed result
back. The patient never leaves your UI and never sees a browser.

iOS, iPadOS and Android.

```
Your Flutter app
      │
      │  SignosoftSigner.open(token: bioid, baseUrl: shell)
      ▼
signosoft_signer   Flutter plugin (Dart API)
      │
      ├── SignosoftSigner   Swift core (SwiftPM, hosts a WKWebView)
      └── SignosoftSigner   Kotlin core (Gradle, hosts a WebView)
      │
      ▼
Signosoft signing shell  ──►  Signosoft REST API
```

## What's in this repository

| Directory | What it is | Who consumes it |
|---|---|---|
| `signosoft_signer/` | Flutter plugin — the Dart API | Flutter apps |
| `ios/` | Swift core — `SignosoftSigner`, a SwiftPM package | native iOS apps |
| `android/` | Kotlin core — `signosoft-signer`, a Gradle library | native Android apps |
| `examples/medicly/` | reference host app — patient view, PDF, Sign button | you, first |
| `docs/` | getting started, and the full integration guide | you, first |

**The directories must stay side by side.** The plugin reaches the Swift core
through a relative symlink and the Kotlin core through a relative source
directory; moving or splitting them breaks the build. See
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
      ref: v0.4.0-alpha
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
you asking it to.

Your app needs an **iOS 16.0** deployment target, **Android API 24**, and a few
`Info.plist` keys and Android manifest permissions — all covered in
[docs/INTEGRATION.md](docs/INTEGRATION.md).

Native iOS apps add `ios/` as a local Swift package and `import SignosoftSigner`.
Native Android apps add `android/signosoft-signer` as a Gradle module.

## Use it

```dart
import 'package:signosoft_signer/signosoft_signer.dart';

final result = await SignosoftSigner.open(
  token: bioid,                            // your backend minted this
  baseUrl: Uri.parse('https://embed.example.com'),
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

`open()` never throws. Every failure arrives as `Failed` with a
`SignosoftErrorCode`.

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

Native Kotlin:

```kotlin
private val signer = registerForActivityResult(SignosoftSignerContract()) { result ->
    when (result) {
        is SignosoftSignerResult.Signed -> result.info.documentToken
        is SignosoftSignerResult.Rejected -> …
        SignosoftSignerResult.Cancelled -> …
        is SignosoftSignerResult.Failed -> result.code  // a SignosoftErrorCode
    }
}

signer.launch(SignosoftSignerRequest(token = bioid, baseUrl = shell))
```

Compose consumes the same contract through `rememberLauncherForActivityResult`.

## Where the signed PDF comes from

Two routes, and you should design for the first:

1. **`documentToken` + your backend.** On `Signed`, hand `documentToken` to your
   own server, which calls the Signosoft `downloadDoc` API with your
   credentials. This is the supported route and the only one that works for
   documents of any size.
2. **`signedPdfPath`** — a copy the SDK writes into the app's temporary
   directory (the cache directory on Android), for "attach to the chart right
   now". It is **null** when the document could not be fetched or exceeds 32 MB.
   A null path never means the signature failed.

`downloadUrl` exists on the result type and is **always null today** — the
backend does not mint one yet. Never show `documentToken` to a user or put it in
a URL: it is an identifier, not a link.

## Documentation

- [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) — one page for a developer
  picking this up cold: what a `bioid` is, who mints it, what you need from
  Signosoft.
- [docs/INTEGRATION.md](docs/INTEGRATION.md) — the full guide: install,
  `Info.plist`, App Transport Security, every outcome, troubleshooting, known
  limitations.
- [examples/medicly/](examples/medicly/) — the reference host app, and the
  fastest way to see the whole flow working.
- `signosoft_signer/CHANGELOG.md`, `ios/CHANGELOG.md`, `android/CHANGELOG.md`.

## Status

An **alpha** for a named pilot. Use requires a paid commercial agreement with
Signosoft and an active service account; see `LICENSE`. Not licensed for
redistribution.

**`baseUrl` has no value yet.** The hosted signing shell is still being stood up,
so there is nothing to point the SDK at until Signosoft gives you a URL. Ask for
it before you plan integration milestones.

**Android is newer and much less verified than iOS** — it compiles and its unit
tests pass, but the ceremony has never been displayed on an emulator or a device.
[Known limitations](docs/INTEGRATION.md#known-limitations) lists honestly what is
verified and what is not, per platform.

Bugs and questions: **info@signosoft.com**. Include the `SignosoftErrorCode`,
the `documentToken` if you have one, and the diagnostic log described in the
integration guide.
