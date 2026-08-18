# CLAUDE.md — house rules for this repository

For anyone, human or agent, picking up the Signosoft Mobile SDK. Read this
first, then `docs/TODO.txt` for what is actually true and outstanding today.

**`docs/TODO.txt` is the authority on current state.** Where a document in
`docs/` disagrees with it, the document is stale.

---

## Who does git

**Petr does all git work.** Commits, branches, tags, merges, pushes. Nobody
else — no agent, no assistant — runs a `git` command that writes. `git diff`,
`git log` and `git status` are fine and encouraged.

This is not a formality. The code goes to a paying client, so the person
responsible signs off every commit himself. If your change is finished, say so
and leave it in the working tree.

**Petr also runs the on-device tests.** Simulator runs are fair game for anyone;
a physical device is his.

---

## What this is

Three layers. A Flutter app calls one method, a full-screen signature ceremony
appears, a typed result comes back.

```
Your Flutter app
      │  SignosoftSigner.open(token: bioid, baseUrl: shell)
      ▼
signosoft_signer/          Flutter plugin — the Dart API
      │                    method channel "com.signosoft.signer"
      ▼
ios/                       Swift core — SwiftPM package, hosts a WKWebView
      │                    bridge handler name "signosoft"
      ▼
the Signosoft signing shell (Angular)  ──►  Signosoft REST API
```

| Directory | What it is |
|---|---|
| `signosoft_signer/` | the Flutter plugin. iOS only — `open()` returns `unsupportedPlatform` elsewhere |
| `signosoft_signer/example/` | bare example: two fields, the four outcomes, nothing else |
| `ios/` | the Swift core, `SignosoftSigner`. Also consumable directly by native iOS apps |
| `examples/medicly/` | the reference host app, and what a client is shown |
| `tools/` | `mint-bioid.mjs`, a Signosoft-internal token minter. Needs credentials |
| `docs/` | client-facing guides, plus `TODO.txt` and the hardening record |

### The two packages must stay siblings

`signosoft_signer/ios/signosoft_signer/SignosoftSignerCore` is a **symlink to
`../../../ios`**. There is exactly one copy of the Swift core on disk and both
consumers use it.

The symlink lives *inside* the plugin package deliberately. Flutter copies the
whole plugin into `ios/Flutter/ephemeral/Packages/.packages/` before building,
and SwiftPM resolves relative dependency paths against that relocated location —
so a path climbing out of the package root resolves into `ephemeral/` and fails,
while one that stays inside resolves through the symlink onto the real
directory. CI asserts the symlink is a symlink, because a checkout that
dereferenced it still compiles here and then breaks for every customer.

**Never replace it with a copy.** Never `git add` a dereferenced version.

---

## The gates

Four suites. Run the ones your change can affect; say which you ran.

```bash
cd ios && swift test
```
14 tests. Runs on **macOS**, which means every `#if canImport(UIKit)` source is
compiled out — the view controller, the bridge, the timeout watchdog, all
invisible. Cheap, and it only covers models and parsing.

```bash
cd ios && xcodebuild test -scheme SignosoftSigner -destination "platform=iOS Simulator,id=<udid>"
```
32 tests. The **only** gate that executes the WebView layer. Pick a udid from
`xcrun simctl list devices available`. Runs in CI on every push.

```bash
cd signosoft_signer && flutter analyze && flutter test
```
20 tests. The Dart API and the wire format.

```bash
cd examples/medicly && flutter analyze && flutter test
```
6 tests. Layout of the reference app at phone and tablet widths.

Do not print a test count you did not see. An agent reporting "all green"
against a gate it could not have run is the normal failure mode here.

---

## Traps that have each cost an hour

**Never `flutter clean` in either example.** `examples/medicly/build` and
`signosoft_signer/example/build` are **symlinks** out to `~/.flutter-build`,
because codesign rejects frameworks built below an iCloud-synced directory.
Deleting the symlink fails the Xcode build with status 255 and no useful error.

**Uninstall the app between simulator runs.**

```bash
xcrun simctl uninstall <udid> com.signosoft.mediclyDemo
```

Stale WebKit cache survives a reinstall and makes the shell resolve an empty
`docLink`. The server reports that as `DOC_LINK_NOT_EXIST` — the same code it
uses for a genuinely dead token, which is what makes the diagnosis slow.

**Never pass a token as an environment-variable prefix.**

```bash
# WRONG — silently passes an empty token, greys out the Sign button
BIOID=abc flutter run --dart-define=BIOID=$BIOID

# RIGHT
flutter run --dart-define=BIOID=$(node tools/mint-bioid.mjs | tail -1)
```

The prefix assignment applies only after `$BIOID` has already expanded.
`mint-bioid.mjs` prints progress lines before the token, hence `tail -1`.

**Gradle here needs JDK 17.** System Java is 25. Export `JAVA_HOME` and
`ANDROID_HOME` before any `./gradlew`. Only relevant on the unmerged Android
branch.

---

## What a `bioid` is

A 64-character hex document-link token: one document, one signer, one session.

- **A backend mints it** by calling `createDocLink`. The SDK cannot, and neither
  can the app.
- **It is consumed by a terminal outcome.** Signing or rejecting uses it up;
  opening and cancelling does not. It is **not** single-use on open — three
  consecutive opens have been verified to work.
- **Treat it as a secret.** Anyone holding it can sign that document. It
  currently travels in a URL query string, so it lands in server access logs,
  CDN logs and `Referer` headers. Do not add more places it can leak.

`documentToken`, by contrast, is safe to log and to share in a bug report. It is
an identifier, not a credential, and it is never a URL.

---

## House patterns

**Dart.** Sealed classes and exhaustive pattern matching — `SignosoftSignResult`
is `sealed` with `Signed`, `Rejected`, `Cancelled`, `Failed`. Add a variant and
every `switch` in every consumer breaks at compile time, which is the point.
Errors never throw: `open()` is documented never to throw and returns
`Failed(code, message)` instead. The codes are `invalidToken`, `invalidBaseUrl`,
`loadFailed`, `loadTimeout`, `sessionFailed`, `alreadyOpen`, `noPresenter`,
`unsupportedPlatform`, `notRegistered`, `unknown`.

Parsing tolerates missing and mistyped fields on purpose — a completed signature
must never be lost to a malformed middle name. The one exception is
`documentToken`: empty means failure, not success.

**Swift.** XCTest only, matching the existing test files. No second test
framework.

Anything that must be reachable from `swift test` has to live **outside**
`#if canImport(UIKit)`. That is why the model layer is WebKit- and UIKit-free:
logic placed inside the guard is unreachable on macOS and therefore untestable
by the cheap gate. When you need to test something that touches UIKit, use the
simulator gate rather than moving the code out from behind its guard.

**The view controller reports but never dismisses itself.** That is deliberate —
it is what makes `SignosoftSignerSheet` work inside a `.fullScreenCover` where
the caller owns presentation state. Do not "fix" it by dismissing.

---

## Not supported, and why the reason matters

Each of these gets re-added helpfully by someone who was told the rule without
the reason.

- **Android.** The plugin declares iOS only. A Kotlin library exists, unmerged,
  on `feature/android-sdk`. Out of scope by decision, not by accident.
- **CocoaPods.** The podspec was removed. CocoaPods discards source files whose
  real path escapes the pod root, so the shared Swift core could never compile
  into the pod — it had never once built. Use Flutter 3.44+ with Swift Package
  Manager.
- **`downloadUrl`.** Modelled on the result type, always null. The backend does
  not mint one. Do not delete the field; do not populate it client-side.
- **Certificate pinning.** Hard to do correctly inside a WebView and breaks on
  rotation. A defensible gap, not a defect.
- **The `biometric` signature field.** It needs an external hardware signature
  pad, and the WASM fallback driver rejects our shell's origin. Server-side, not
  ours — see `docs/TODO.txt` for the diagnosis and the one-line curl that proves
  it.

---

## Floors

iOS/iPadOS 16.0 · Flutter 3.44 · Dart 3.12 · Swift tools 5.9 · Xcode 15+.

Built and exercised only on Flutter 3.44.8 / Dart 3.12.2 / Xcode 26.6. Lower
versions inside those ranges are untested — say "untested", not "supported".

---

## Reporting work

Say which gates you ran and paste their real output. Name what you could not
verify. "4 failures, and here is whose they are" is worth more than a quiet
patch that makes them go away.
