# SDK hardening — change record

**Date:** 2026-08-13
**Branch:** `dev` (working tree, **uncommitted**)
**Scope:** iOS Swift core, Flutter plugin's iOS side, Dart layer, both example apps
**Android:** not touched — it lives on `feature/android-sdk`

This document exists as insurance. Another agent was working in the same
directory at the time, nothing was committed, and a string-level overwrite of a
shared file produces no merge conflict to warn anyone. Appendix A is the diff and
Appendix B is the full text of the two new files, so everything here is
recoverable if it gets trampled.

It was written from the change log of the edits actually applied, not by reading
`git diff` back — see *Attribution* below for why that distinction matters.

---

## Verification status

| Check | Result |
|---|---|
| `swift test` (macOS, model + parsing layer) | 20 passed, 0 failed — baseline is 14, so +6 |
| `xcodebuild -destination 'generic/platform=iOS'` | **BUILD SUCCEEDED**, no warnings |
| `flutter analyze` (plugin) | No issues found |
| `flutter test` (plugin) | 22 passed — baseline is 20, so +2 |
| `flutter analyze` (examples/medicly) | No issues found |
| On a real device or simulator | **Not run.** See *Untested* below. |

Baselines re-measured on the reverted tree, so they are exact rather than
remembered.

The iOS build matters more than the test count here: `swift test` runs on macOS,
where every `#if canImport(UIKit)` source — including the entire view controller
— is compiled out. Only the `xcodebuild` run actually type-checks the changed
WebView code.

---

## ⚠️ Untested, and the first thing to revert

Every change below is verified to **compile and pass unit tests**. None is
verified to **work in a live signing ceremony**, because that needs a real bioid
and a device.

One change carries real functional risk:

> **The bridge origin check** in `SignosoftSignerViewController.userContentController`
> drops any bridge message whose frame origin is not the shell's. If
> `HostBridgeService` posts from a frame on a *different* origin than `baseUrl`,
> every message is dropped, `ready` never arrives, and the ceremony dies at the
> 45-second `loadTimeout`.

**How to tell in ten seconds.** Run with `onDiagnostic` on in a debug build and
watch the console:

| Console shows | Meaning |
|---|---|
| `bridgeMessageRejected` with `reason: origin` | **This change is the cause.** The payload names the rejecting origin. |
| `navigationBlocked` | The navigation allowlist is the cause; payload names the URL. |
| Nothing at all | Not these changes. The shell never talked to us at all. |
| `ready`, then silence | Not these changes. Something later in the ceremony. |

Both event names are new in this change set, so they are free diagnosis.

**A note on "spent bioid" as an explanation.** I initially offered that as the
likely cause of a 45-second timeout. Someone else on this codebase then
established empirically that a bioid is **not single-use — three consecutive
opens all succeeded**. So a merely-reused token is not an explanation, and that
hypothesis should be dropped unless the token was actually signed or rejected
(which `tools/README.md` says is what consumes one).

That finding also sharpens security finding **M-1** in the audit report: a
replayable token sitting in a URL query string — and therefore in server access
logs, CDN logs and `Referer` headers — is worse than a single-use one, because
recovering it from a log still yields a working credential.

**What was checked, and what it does not prove.** `https://www.signosoft.com/mobilesdk/`
answers HTTP 200 with **zero redirects**, and the only cross-origin references in
its HTML are `fonts.googleapis.com` / `fonts.gstatic.com` — subresources, which
never reach the navigation delegate and never post bridge messages. Angular's
in-app routing uses `pushState`, which also never reaches that delegate. So the
*initial load* is safe and the navigation allowlist should be inert in practice.
That says nothing about which frame the bridge posts from.

**To revert just that check** without losing the rest: in
`userContentController(_:didReceive:)`, replace the `guard shellOrigin?.matches(sender)`
block with a call to `onEvent?` that logs the mismatch and falls through. The
navigation allowlist, which is the larger half of the same defence, keeps working.

---

## Attribution — settled

An earlier draft of this document said the changes were interleaved with
pre-existing uncommitted work in the same files, and that Appendix A therefore
might contain edits that were not mine. **That was wrong**, and reverting proved
it: after backing out every change listed here, `git diff` on `ios/`,
`signosoft_signer/` and `examples/medicly/lib/` came back **completely empty**.
Those files are byte-identical to `HEAD`.

So Appendix A is a clean, exact record of this change set and nothing else.

What misled me: the git snapshot I was handed at the start of the session listed
`ShellOrigin.swift` and `ShellOriginTests.swift` as untracked *before I created
them*, and listed the eight code files as modified before I edited them. That
snapshot reflected a later state than its label suggested. I flagged the
inconsistency at the time but drew the wrong conclusion from it. The empty diff
is the authoritative answer.

**Genuinely pre-existing, and untouched by me:** `docs/INTEGRATION.md`,
`examples/medicly/README.md`, `tools/.mint-bioid.env.example`.

---

## New files

### `ios/Sources/SignosoftSigner/Model/ShellOrigin.swift`

**Why.** The SDK had no notion of "the origin I trust." Origin comparison was
needed in three places — navigation policy, the bridge, media-capture permission
— and existed in none of them.

**What.** A value type holding scheme, host and port, with `matches(_:)` for
same-origin comparison and `isUsable(_:)` for `baseUrl` validation.

**How.** Deliberately free of WebKit and UIKit. That is not stylistic: the enum
`SignosoftSigner` lives inside `#if canImport(UIKit)` and therefore does not
exist on macOS, so logic placed there is unreachable from `swift test`. Keeping
`ShellOrigin` clean is what makes the 7 new tests possible.

Two details worth keeping if this is ever rewritten:

- **Port normalisation.** `WKSecurityOrigin.port` reports `0` for a scheme's
  default port; `URL.port` reports `nil`. Both must normalise to 443/80 or the
  shell fails to match itself.
- **Case folding.** Host and scheme are lowercased on the way in, so
  `HTTPS://WWW.Signosoft.COM` matches.

### `ios/Tests/SignosoftSignerTests/ShellOriginTests.swift`

6 tests: https accepted; scheme-less/host-less/`file://` rejected; public
cleartext rejected but loopback allowed; case-insensitive matching plus
subdomain-is-a-different-origin; the WebKit-`0` vs URL-`nil` port equivalence;
explicit port mismatch not swallowed by normalisation.

---

## Security changes

### 1. The bridge accepted messages from any origin — *High*

`SignosoftSignerViewController.swift`, `userContentController(_:didReceive:)`

**Why.** The handler checked `message.name` and nothing else. Any frame the shell
embeds, and any page it navigated to, could post
`{"event":"signed", "data":{…}}` and the host would record a signature that never
happened — with an attacker-chosen `documentToken`, signer name and email, and an
arbitrary PDF written to disk and shown to the clinician as the signed document.
The inverse (`{"event":"error"}`) destroys a genuine ceremony.

The code already knew the right pattern: `onPermissionRequest` on Android checked
`isShellOrigin` before granting the camera. The far more consequential bridge did
not.

**How.** Compare `message.frameInfo.securityOrigin` against the shell origin
before parsing. Rejected messages emit a `bridgeMessageRejected` diagnostic
carrying the offending origin — a message that vanishes silently is the hardest
kind of integration bug to find.

### 2. No navigation allowlist — *High* (same defect)

`SignosoftSignerViewController.swift`, new `decidePolicyFor navigationAction`

**Why.** Only the *response* variant of the policy delegate existed. The WebView
followed any redirect, any `window.location`, any tapped link, to any origin —
and the bridge stayed attached across that navigation.

**How.** Cancel off-origin **main-frame** navigations.

Two deliberate carve-outs:

- **Subframes are allowed through.** A cross-origin iframe the shell embeds on
  purpose keeps working. The bridge origin check (#1) is what stops such a frame
  from *reporting* anything. Policing subframe navigation here would risk
  breaking the shell for no additional protection.
- **A user-tapped `https` link opens in Safari** rather than being silently
  dropped, so a genuine "terms and conditions" link still works — just outside
  the ceremony.

`about:` is allowed so `finish` can blank the page (see #13).

### 3. `isInspectable = true` in release builds — *High*

**Why.** Unconditional, no `#if DEBUG`. Every app shipping this SDK exposed the
live ceremony to Safari's Web Inspector. No jailbreak needed — Web Inspector
enabled in Settings plus a USB Mac is enough.

The sharpest angle is not an outside attacker: it is **the signer**. The person
holding the device is the party whose identity the ceremony asserts. DevTools on
a production build lets them rewrite the DOM and post bridge messages by hand —
a self-service repudiation primitive against a signature product.

Android already gated the identical capability behind `FLAG_DEBUGGABLE`, with a
comment reading "a release build must not expose the ceremony." iOS violated the
team's own stated policy.

**How.** Wrapped in `#if DEBUG`.

### 4. Camera and microphone granted without an origin check — *Medium*

**Why.** `requestMediaCapturePermissionFor` returned `.prompt` unconditionally.
Chained with #2, a hostile origin could raise a camera prompt mid-ceremony.

**How.** `.prompt` for the shell origin, `.deny` otherwise — matching Android.

### 5. Persistent, app-shared WebView storage — *Medium*

**Why.** The default `WKWebsiteDataStore` persists to disk and is shared with
every other WebView in the host app. Session cookies and localStorage from a
completed ceremony survived app restarts and were readable by unrelated in-app
code, including other SDKs the integrator embeds.

**How.** `configuration.websiteDataStore = .nonPersistent()`. Each ceremony gets
a fresh bioid, so nothing legitimately needs to persist.

### 6. Signed PDF readable while the device is locked — *Medium*

`SignedPdfStore.swift`

**Why.** The default protection class is
`NSFileProtectionCompleteUntilFirstUserAuthentication` — readable from first
unlock until reboot, even while subsequently locked. This is a signed medical
document.

**How.** Added `.completeFileProtection` to the write options.

*Still open:* nothing ever deletes these files, and the name comes from a
shell-supplied value. Path traversal is correctly handled, but the directory
accumulates documents. A `clearCachedDocuments()` on the public surface would
close it.

### 7. No app-switcher snapshot protection — *Medium*

**Why.** iOS writes a screenshot to disk when the app backgrounds. A medical
document and a handwritten signature should not be in it. Android's `FLAG_SECURE`
covers the same ground and was also missing there.

**How.** A cover view added on `willResignActiveNotification`, removed on
`didBecomeActiveNotification`. Observers removed in `deinit`.

### 8. `baseUrl` accepted anything — *Medium*

`SignosoftSigner.swift` (new `isUsableBaseURL`), `SignosoftSignerPlugin.swift`,
and `loadSigner`

**Why.** Two separate problems in one gap.

*Correctness:* `URL(string: "notaurl")` succeeds — it becomes a scheme-less
relative URL. The ceremony opened, failed to load, and reported `loadFailed`
seconds later, blaming the network for a typo. Android rejected the same input
immediately with `invalidBaseUrl`. Same input, different error code, depending on
platform.

*Transport:* the SDK would happily load `http://` and append the bioid to it,
delegating all transport security to whatever ATS policy the host app happened to
have.

**How.** Require https, or http for loopback only (`localhost`, `127.0.0.1`,
`::1`, `10.0.2.2`, `*.localhost`). Checked in the plugin *and* in `loadSigner`,
so native hosts calling the core directly get the same treatment.

Rejecting public cleartext costs nothing real: per `docs/INTEGRATION.md`, such a
page is not a secure context, so WebCrypto does not exist and the shell could
never complete a signature there anyway. Better to say so up front.

---

## Robustness changes

### 9. The host's completion could hang forever — *highest blast radius*

**Why.** The controller reports but never dismisses itself — by design, so
`SignosoftSignerSheet` works inside `.fullScreenCover`. But nothing handled being
torn down *without* a result. If the host dismissed the signer, or a Flutter
route change took it away, `onResult` never fired. Consequences, in order:

1. The Dart `Future` from `open()` never completes. The caller awaits forever.
2. `isPresenting` in the plugin never resets.
3. Every subsequent `open()` returns `alreadyOpen` — **for the rest of the app's
   lifetime**. Signing is permanently broken until restart.

Android never had this bug: a destroyed activity yields `RESULT_CANCELED`, which
`parseResult` maps to `Cancelled`.

**How.** `viewDidDisappear` calls `finish(.cancelled)` when `isBeingDismissed ||
isMovingFromParent`. `finish` is idempotent, so the normal path — report, then
dismiss — is unaffected; this only fires when nothing else did.

*Known imperfection, inherited:* reporting `Cancelled` here is optimistic. If the
controller is torn down after the document was signed server-side but before the
bridge message arrived, the host is told `Cancelled` — and the docs promise
`Cancelled` means "server state unchanged." Android has the identical flaw. A
distinct `Interrupted` outcome would fix both, but that is a public API change
and a product decision.

### 10. 32 MB base64 decode and disk write on the main thread — *will jank or ANR*

**Why.** WebKit delivers bridge messages on the main thread. `SignedInfo.fromBridge`
calls `SignedPdfStore.write`, which base64-decodes up to 32 MB and writes it to
disk — synchronously, inline. The UI froze at the exact moment the signer expects
confirmation.

**How.** New `deliverOutcome` builds the `SignedInfo` on
`DispatchQueue.global(qos: .userInitiated)` and hops back to main to call
`finish`. Guarded by `didFinish` on entry and re-checked via `[weak self]` on
return.

### 11. An empty `documentToken` was reported as success — *Medium*

**Why.** Every field defaults on the wire — deliberately, so a missing middle name
never loses a signature. But `documentToken` is the *only* handle the host has on
the document. A corrupt payload produced a plausible-looking `Signed` whose token
was `""`, and the host then called its backend with nothing.

**How.** `deliverOutcome` rejects an empty `documentToken` with
`sessionFailed`. Better a loud failure than a hollow success. The existing
`//WARN` comment in `SignedInfo.swift` flagged exactly this risk.

### 12. `loadTimeout <= 0` meant two different things — *parity bug*

**Why.** The view controller treated it as "disable the watchdog" and silently
returned. The Flutter plugin's `loadTimeout(_:)` treated it as "use the default."
Same value, opposite behaviour, depending on entry point — and the native path
left the patient on a blank screen forever, which is the exact failure the
watchdog exists to prevent.

**How.** Clamp in the initialiser: `loadTimeout > 0 ? loadTimeout : defaultLoadTimeout`.
There is now always a watchdog. Removed the now-dead `guard` in
`startTimeoutTimer`.

### 13. The page kept running after the result was reported — *Medium*

**Why.** `finish` reported and stopped. The page — possibly holding a live camera
or microphone stream — kept running. With `SignosoftSignerSheet` the host owns
dismissal, so a host that reports the result but forgets to flip its binding
leaves a live ceremony running unbounded.

**How.** `finish` now calls `stopLoading()` and loads an empty document.

### 14. Dart `open()` was documented "Never throws" but did

`channel.dart`

**Why.** Only `PlatformException` and `MissingPluginException` were caught. A
codec error or a malformed reply escaped into the caller's `await` — breaking the
contract at the one place hosts were told to rely on it.

Separately, `onDiagnostic` was invoked unguarded inside an `async` method-call
handler. A host callback that throws surfaced as an unhandled async error
attributed to the SDK.

**How.** A catch-all returning `Failed(unknown, …)` with the error text, and a
`try/catch` around the `onDiagnostic` invocation. Diagnostics are a debugging
aid; they must not affect the session. Two tests added for both.

### 15. Example apps logged signer PII in release builds — *Low, but it is a template*

`examples/medicly/lib/report_screen.dart`, `signosoft_signer/example/lib/main.dart`

**Why.** `debugPrint` is **not** stripped from Flutter release builds. The
diagnostic payload elides only `pdfBase64`; `documentToken`, `lastSignerEmail`
and the signer's name all pass through into the device log. This contradicts
`docs/INTEGRATION.md`, which says `documentToken` must never be shown to a user.

Example code is a copy-paste template, which is why it is worth fixing.

**How.** Both call sites now pass `kDebugMode ? (d) => debugPrint(…) : null`.

---

## Deliberately not changed

| Item | Why not |
|---|---|
| bioid in the URL query string | Needs a protocol change coordinated with the web shell — fragment, POST bootstrap, or a session exchange. Cannot be done unilaterally. |
| `documentToken` shown in the plugin example's UI | Contradicts the docs, but displaying the payload is that example's entire purpose. |
| Certificate pinning | Hard to do correctly inside a WebView and breaks on certificate rotation. A defensible gap, not a defect. |
| An `Interrupted` outcome distinct from `Cancelled` | Public API change; product decision. See #9. |
| Deleting cached signed PDFs | Needs a public `clearCachedDocuments()` and a documented lifecycle. See #6. |
| Committing lockfiles for the example **apps** | `pubspec.lock` and `Package.resolved` are gitignored repo-wide. Right for libraries, wrong for apps — but it is a repo-policy call. |

---

## Android

Untouched. The Android SDK is on `feature/android-sdk`; the working tree's
`android/` directory holds only stale Gradle build output.

It shares defects #1 and #2 — no `shouldOverrideUrlLoading`, and
`addJavascriptInterface` reachable from every frame including cross-origin
iframes. It additionally lacks `FLAG_SECURE`, never clears cookies or
`WebStorage`, and leaves `allowContentAccess` at its default of **on**.

The clean fix for the bridge there is `WebViewCompat.addWebMessageListener` with
`allowedOriginRules` — it injects `window.SignosoftAndroid` with a `postMessage(String)`
method, the **same JS shape** the shell already calls, so the shell needs no
change. It requires the `androidx.webkit` dependency and a
`WebViewFeature.isFeatureSupported` fallback, and it needs device testing.

---


---

## Appendix A — full working-tree diff for the files above

Captured after the changes were made and verified, against a tree that was
otherwise identical to `HEAD` — see *Attribution — settled*. These hunks are
therefore exactly this change set and nothing else, and applying them to a clean
`dev` checkout reproduces it:

```bash
git apply the-diff-below.patch
```

The two new files in Appendix B are not in this diff; create them from their full
text there.

```diff
diff --git a/examples/medicly/lib/report_screen.dart b/examples/medicly/lib/report_screen.dart
index fb0d928..7832b5f 100644
--- a/examples/medicly/lib/report_screen.dart
+++ b/examples/medicly/lib/report_screen.dart
@@ -1,3 +1,4 @@
+import 'package:flutter/foundation.dart';
 import 'package:flutter/material.dart';
 import 'package:pdfrx/pdfrx.dart';
 import 'package:signosoft_signer/signosoft_signer.dart';
@@ -33,7 +34,11 @@ class _ReportScreenState extends State<ReportScreen> {
       // Every bridge event the shell sends, in the Flutter console. The only
       // way to see why a ceremony hangs: no `ready` means the shell never
       // established the session.
-      onDiagnostic: (d) => debugPrint('[signosoft] $d'),
+      //
+      // Debug builds only. `debugPrint` is not stripped from release builds,
+      // and the payload carries the documentToken and the signer's name and
+      // email straight into the device log.
+      onDiagnostic: kDebugMode ? (d) => debugPrint('[signosoft] $d') : null,
     );
 
     if (!mounted) return;
diff --git a/ios/Sources/SignosoftSigner/Model/SignedPdfStore.swift b/ios/Sources/SignosoftSigner/Model/SignedPdfStore.swift
index 94a0bda..90036b8 100644
--- a/ios/Sources/SignosoftSigner/Model/SignedPdfStore.swift
+++ b/ios/Sources/SignosoftSigner/Model/SignedPdfStore.swift
@@ -32,15 +32,20 @@ struct SignedPdfStore {
 
     func write(base64: String?, fileName: String?) -> URL? {
         guard let base64, !base64.isEmpty else { return nil }
-        // Four base64 characters carry three bytes; check before allocating.
-        guard base64.count / 4 * 3 <= maximumBytes else { return nil }   //WARN: Check whether operator precedence doesn't make a difference here
+        // Four base64 characters carry three bytes. Integer division rounds
+        // down, so this can only ever under-estimate — it is an allocation
+        // guard, and the exact check on `data.count` below is the real ceiling.
+        guard base64.count / 4 * 3 <= maximumBytes else { return nil }
         guard let data = Data(base64Encoded: base64), !data.isEmpty,
               data.count <= maximumBytes
         else { return nil }
 
         let url = directory.appendingPathComponent(Self.safeName(fileName))
         do {
-            try data.write(to: url, options: .atomic)
+            // A signed medical document should not be readable while the device
+            // is locked. The default protection class keeps it readable from
+            // first unlock until reboot.
+            try data.write(to: url, options: [.atomic, .completeFileProtection])
             return url
         } catch {
             return nil
diff --git a/ios/Sources/SignosoftSigner/SignosoftSigner.swift b/ios/Sources/SignosoftSigner/SignosoftSigner.swift
index 5ddf3e8..2a30b95 100644
--- a/ios/Sources/SignosoftSigner/SignosoftSigner.swift
+++ b/ios/Sources/SignosoftSigner/SignosoftSigner.swift
@@ -32,5 +32,10 @@ public enum SignosoftSigner {
         controller.onEvent = onEvent
         presenter.present(controller, animated: true)
     }
+
+    /// Whether the signer can load this origin at all. See `ShellOrigin`.
+    public static func isUsableBaseURL(_ url: URL) -> Bool {
+        ShellOrigin.isUsable(url)
+    }
 }
 #endif
diff --git a/ios/Sources/SignosoftSigner/UI/SignosoftSignerViewController.swift b/ios/Sources/SignosoftSigner/UI/SignosoftSignerViewController.swift
index af5adb9..d31be75 100644
--- a/ios/Sources/SignosoftSigner/UI/SignosoftSignerViewController.swift
+++ b/ios/Sources/SignosoftSigner/UI/SignosoftSignerViewController.swift
@@ -18,6 +18,10 @@ public final class SignosoftSignerViewController: UIViewController {
 
     private let token: String
     private let baseURL: URL
+    /// The only origin trusted to navigate the main frame, post bridge
+    /// messages, or ask for the camera. Nil only for a `baseURL` that has no
+    /// host, which `loadSigner` rejects before anything loads.
+    private let shellOrigin: ShellOrigin?
     private let loadTimeout: TimeInterval
     private let pdfStore: SignedPdfStore
     private let onResult: (SignosoftSignerResult) -> Void
@@ -30,6 +34,8 @@ public final class SignosoftSignerViewController: UIViewController {
     private let spinner = UIActivityIndicatorView(style: .large)
     private var timeoutTimer: Timer?
     private var didFinish = false
+    /// Hides the ceremony from the app switcher's snapshot. See `setUpPrivacyCover`.
+    private var privacyCover: UIView?
 
     public init(
         token: String,
@@ -39,7 +45,11 @@ public final class SignosoftSignerViewController: UIViewController {
     ) {
         self.token = token
         self.baseURL = baseURL
-        self.loadTimeout = loadTimeout
+        self.shellOrigin = ShellOrigin(url: baseURL)
+        // A non-positive timeout used to disable the watchdog silently, while
+        // the same value through the Flutter plugin fell back to the default.
+        // One meaning now: there is always a watchdog.
+        self.loadTimeout = loadTimeout > 0 ? loadTimeout : Self.defaultLoadTimeout
         self.pdfStore = SignedPdfStore()
         self.onResult = onResult
         super.init(nibName: nil, bundle: nil)
@@ -51,6 +61,7 @@ public final class SignosoftSignerViewController: UIViewController {
 
     deinit {
         timeoutTimer?.invalidate()
+        NotificationCenter.default.removeObserver(self)
         webView?.configuration.userContentController
             .removeScriptMessageHandler(forName: Self.handlerName)
     }
@@ -61,13 +72,33 @@ public final class SignosoftSignerViewController: UIViewController {
 
         setUpWebView()
         setUpOverlay()
+        setUpPrivacyCover()
         loadSigner()
     }
 
+    /// The caller owns presentation, so this controller can be dismissed or
+    /// popped without the ceremony ever reporting — and then `onResult` would
+    /// never fire, the host's completion would hang forever, and the SDK would
+    /// latch closed on `alreadyOpen`. Android's activity result covers exactly
+    /// this case; iOS has to do it by hand.
+    ///
+    /// `finish` is idempotent, so the ordinary path — report, then dismiss —
+    /// still delivers the real outcome and this is a no-op.
+    override public func viewDidDisappear(_ animated: Bool) {
+        super.viewDidDisappear(animated)
+        if isBeingDismissed || isMovingFromParent {
+            finish(.cancelled)
+        }
+    }
+
     private func setUpWebView() {
         let configuration = WKWebViewConfiguration()
         configuration.allowsInlineMediaPlayback = true
         configuration.mediaTypesRequiringUserActionForPlayback = []
+        // Cookies and local storage from a ceremony must not outlive it, and
+        // must not be visible to any other WebView the host app runs: the
+        // default store is shared process-wide and persists to disk.
+        configuration.websiteDataStore = .nonPersistent()
         configuration.userContentController.add(
             WeakScriptMessageHandler(self),
             name: Self.handlerName
@@ -78,10 +109,15 @@ public final class SignosoftSignerViewController: UIViewController {
         webView.uiDelegate = self
         webView.allowsBackForwardNavigationGestures = false
         webView.translatesAutoresizingMaskIntoConstraints = false
+        #if DEBUG
         if #available(iOS 16.4, *) {
-            // Lets you attach Safari's Web Inspector to the WebView.
+            // Lets you attach Safari's Web Inspector to the WebView. Debug
+            // builds only — a release build must not expose the ceremony, which
+            // would let anyone with the device read the bioid and drive the
+            // bridge by hand. Matches the Android side's FLAG_DEBUGGABLE gate.
             webView.isInspectable = true
         }
+        #endif
 
         view.addSubview(webView)
         NSLayoutConstraint.activate([
@@ -117,7 +153,54 @@ public final class SignosoftSignerViewController: UIViewController {
         ])
     }
 
+    /// iOS snapshots the screen when the app goes to the background, and that
+    /// snapshot lands on disk. A medical document and a handwritten signature
+    /// should not be in it. The Android side sets FLAG_SECURE for the same
+    /// reason.
+    private func setUpPrivacyCover() {
+        let centre = NotificationCenter.default
+        centre.addObserver(
+            self,
+            selector: #selector(showPrivacyCover),
+            name: UIApplication.willResignActiveNotification,
+            object: nil
+        )
+        centre.addObserver(
+            self,
+            selector: #selector(hidePrivacyCover),
+            name: UIApplication.didBecomeActiveNotification,
+            object: nil
+        )
+    }
+
+    @objc private func showPrivacyCover() {
+        guard privacyCover == nil, isViewLoaded else { return }
+        let cover = UIView(frame: view.bounds)
+        cover.backgroundColor = .systemBackground
+        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
+        view.addSubview(cover)
+        privacyCover = cover
+    }
+
+    @objc private func hidePrivacyCover() {
+        privacyCover?.removeFromSuperview()
+        privacyCover = nil
+    }
+
     private func loadSigner() {
+        // Rejected here rather than after a failed network load, so the host
+        // gets `invalidBaseUrl` for a bad origin instead of a `loadFailed` that
+        // arrives seconds later and blames the network. This is also what stops
+        // a cleartext origin from ever carrying the bioid.
+        guard SignosoftSigner.isUsableBaseURL(baseURL) else {
+            finish(.error(SignosoftError(
+                code: .invalidBaseUrl,
+                message: "baseUrl must be an https:// origin with a host — got "
+                    + "\(baseURL.absoluteString). Plain http:// is accepted only "
+                    + "for localhost while developing."
+            )))
+            return
+        }
         guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
             finish(.error(SignosoftError(
                 code: .invalidBaseUrl,
@@ -147,7 +230,6 @@ public final class SignosoftSignerViewController: UIViewController {
     /// Without this a wrong `baseURL` leaves the patient on a blank screen
     /// forever: the page never loads, so no bridge event ever arrives.
     private func startTimeoutTimer() {
-        guard loadTimeout > 0 else { return }
         timeoutTimer = Timer.scheduledTimer(
             withTimeInterval: loadTimeout,
             repeats: false
@@ -171,6 +253,12 @@ public final class SignosoftSignerViewController: UIViewController {
         didFinish = true
         timeoutTimer?.invalidate()
         timeoutTimer = nil
+        // Tear the page down rather than leaving it running. It may hold a
+        // camera or microphone stream, and with `SignosoftSignerSheet` the host
+        // owns dismissal — a host that reports the result but forgets to flip
+        // its binding would otherwise leave a live ceremony running unbounded.
+        webView?.stopLoading()
+        webView?.loadHTMLString("", baseURL: nil)
         onResult(result)
     }
 }
@@ -182,9 +270,27 @@ extension SignosoftSignerViewController: WKScriptMessageHandler {
         _ userContentController: WKUserContentController,
         didReceive message: WKScriptMessage
     ) {
-        guard message.name == Self.handlerName,
-              let bridgeMessage = BridgeMessage(body: message.body)
-        else { return }
+        guard message.name == Self.handlerName else { return }
+
+        // Only the shell may drive the session. Without this, any frame the
+        // shell embeds — and any page it navigates to — could report a
+        // signature that never happened, and the host would believe it.
+        let sender = ShellOrigin(
+            scheme: message.frameInfo.securityOrigin.protocol,
+            host: message.frameInfo.securityOrigin.host,
+            port: message.frameInfo.securityOrigin.port
+        )
+        guard shellOrigin?.matches(sender) == true else {
+            // Reported rather than dropped in silence: a bridge message that
+            // vanishes is the hardest kind of integration bug to find.
+            onEvent?("bridgeMessageRejected", ["reason": "origin", "origin": sender.description])
+            return
+        }
+
+        guard let bridgeMessage = BridgeMessage(body: message.body) else {
+            onEvent?("bridgeMessageRejected", ["reason": "unparseable"])
+            return
+        }
 
         onEvent?(bridgeMessage.event, bridgeMessage.diagnosticData)
 
@@ -195,9 +301,9 @@ extension SignosoftSignerViewController: WKScriptMessageHandler {
             spinner.stopAnimating()
             spinner.isHidden = true
         case "signed":
-            finish(.signed(SignedInfo(bridgeData: bridgeMessage.data, pdfStore: pdfStore)))
+            deliverOutcome(bridgeMessage.data, as: SignosoftSignerResult.signed)
         case "rejected":
-            finish(.rejected(SignedInfo(bridgeData: bridgeMessage.data, pdfStore: pdfStore)))
+            deliverOutcome(bridgeMessage.data, as: SignosoftSignerResult.rejected)
         case "cancelled":
             finish(.cancelled)
         case "error":
@@ -210,11 +316,87 @@ extension SignosoftSignerViewController: WKScriptMessageHandler {
             break
         }
     }
+
+    /// Builds the outcome off the main thread and reports it back on it.
+    ///
+    /// Decoding up to 32 MB of base64 and writing it to disk is the single most
+    /// expensive thing the SDK does, and it lands on the main thread because
+    /// that is where WebKit delivers bridge messages. Doing it inline froze the
+    /// UI at the exact moment the signer expects confirmation.
+    private func deliverOutcome(
+        _ data: [String: Any]?,
+        as makeResult: @escaping (SignedInfo) -> SignosoftSignerResult
+    ) {
+        guard !didFinish else { return }
+        let store = pdfStore
+        DispatchQueue.global(qos: .userInitiated).async {
+            let info = SignedInfo(bridgeData: data, pdfStore: store)
+            DispatchQueue.main.async { [weak self] in
+                guard let self else { return }
+                // Every other field may safely default — losing a signer's
+                // middle name must not lose a signature. `documentToken` may
+                // not: it is the only handle the host has on the document, and
+                // a blank one turns a completed ceremony into a backend call
+                // for nothing. Better a loud failure than a hollow success.
+                guard !info.documentToken.isEmpty else {
+                    self.finish(.error(SignosoftError(
+                        code: .sessionFailed,
+                        message: "The signing shell reported an outcome with no "
+                            + "documentToken, so the document cannot be identified."
+                    )))
+                    return
+                }
+                self.finish(makeResult(info))
+            }
+        }
+    }
 }
 
 // MARK: - Navigation
 
 extension SignosoftSignerViewController: WKNavigationDelegate {
+    /// Keeps the main frame on the shell's origin for the whole ceremony.
+    ///
+    /// Without this the WebView follows any redirect or tapped link anywhere,
+    /// and the bridge stays attached across that navigation — so whatever
+    /// landed there could report a signature. A genuine external link still
+    /// works; it just opens in Safari, outside the ceremony.
+    ///
+    /// Subframes are deliberately left alone. A cross-origin frame the shell
+    /// embeds on purpose keeps working, and the bridge's own origin check is
+    /// what stops such a frame from reporting anything.
+    public func webView(
+        _ webView: WKWebView,
+        decidePolicyFor navigationAction: WKNavigationAction,
+        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
+    ) {
+        guard navigationAction.targetFrame?.isMainFrame ?? true else {
+            decisionHandler(.allow)
+            return
+        }
+        guard let url = navigationAction.request.url else {
+            decisionHandler(.cancel)
+            return
+        }
+        // `finish` tears the page down with an empty document, which WebKit
+        // loads as about:blank.
+        if url.scheme == "about" {
+            decisionHandler(.allow)
+            return
+        }
+        guard shellOrigin?.matches(url: url) == true else {
+            decisionHandler(.cancel)
+            onEvent?("navigationBlocked", ["url": url.absoluteString])
+            // A link the signer actually tapped is the one case worth honouring,
+            // and Safari is the safe place for it.
+            if navigationAction.navigationType == .linkActivated, url.scheme == "https" {
+                UIApplication.shared.open(url)
+            }
+            return
+        }
+        decisionHandler(.allow)
+    }
+
     public func webView(
         _ webView: WKWebView,
         didFailProvisionalNavigation navigation: WKNavigation!,
@@ -279,6 +461,9 @@ extension SignosoftSignerViewController: WKNavigationDelegate {
 // MARK: - Camera / microphone prompts
 
 extension SignosoftSignerViewController: WKUIDelegate {
+    /// Only the shell may ask for the camera or the microphone, which is the
+    /// rule the Android side already applied. Anything else is denied without
+    /// troubling the signer with a prompt they cannot evaluate.
     public func webView(
         _ webView: WKWebView,
         requestMediaCapturePermissionFor origin: WKSecurityOrigin,
@@ -286,7 +471,12 @@ extension SignosoftSignerViewController: WKUIDelegate {
         type: WKMediaCaptureType,
         decisionHandler: @escaping (WKPermissionDecision) -> Void
     ) {
-        decisionHandler(.prompt)
+        let requester = ShellOrigin(
+            scheme: origin.protocol,
+            host: origin.host,
+            port: origin.port
+        )
+        decisionHandler(shellOrigin?.matches(requester) == true ? .prompt : .deny)
     }
 }
 #endif
diff --git a/signosoft_signer/example/lib/main.dart b/signosoft_signer/example/lib/main.dart
index 6453e1d..dd97842 100644
--- a/signosoft_signer/example/lib/main.dart
+++ b/signosoft_signer/example/lib/main.dart
@@ -1,3 +1,4 @@
+import 'package:flutter/foundation.dart';
 import 'package:flutter/material.dart';
 import 'package:signosoft_signer/signosoft_signer.dart';
 
@@ -50,8 +51,12 @@ class _SignPageState extends State<SignPage> {
     final result = await SignosoftSigner.open(
       token: _token.text.trim(),
       baseUrl: Uri.parse(_baseUrl.text.trim()),
-      // Diagnostics are for debugging an integration, never for product logic.
-      onDiagnostic: (d) => debugPrint('signosoft: ${d.event} ${d.data ?? ''}'),
+      // Diagnostics are for debugging an integration, never for product logic —
+      // and debug builds only: `debugPrint` survives into release, and the
+      // payload carries the documentToken and the signer's name and email.
+      onDiagnostic: kDebugMode
+          ? (d) => debugPrint('signosoft: ${d.event} ${d.data ?? ''}')
+          : null,
     );
 
     if (!mounted) return;
diff --git a/signosoft_signer/ios/signosoft_signer/Sources/signosoft_signer/SignosoftSignerPlugin.swift b/signosoft_signer/ios/signosoft_signer/Sources/signosoft_signer/SignosoftSignerPlugin.swift
index 428f16b..1c3dd1c 100644
--- a/signosoft_signer/ios/signosoft_signer/Sources/signosoft_signer/SignosoftSignerPlugin.swift
+++ b/signosoft_signer/ios/signosoft_signer/Sources/signosoft_signer/SignosoftSignerPlugin.swift
@@ -41,10 +41,19 @@ public final class SignosoftSignerPlugin: NSObject, FlutterPlugin {
             result(Self.error(.invalidToken, "A bioid token is required."))
             return
         }
+        // `URL(string:)` alone accepts nonsense like "notaurl" — it becomes a
+        // scheme-less relative URL — so the ceremony used to open, fail to
+        // load, and report `loadFailed` seconds later. Android rejected the
+        // same input up front with `invalidBaseUrl`; both platforms now agree.
         guard let baseUrlString = arguments["baseUrl"] as? String,
-              let baseURL = URL(string: baseUrlString)
+              let baseURL = URL(string: baseUrlString),
+              SignosoftSigner.isUsableBaseURL(baseURL)
         else {
-            result(Self.error(.invalidBaseUrl, "A valid baseUrl is required."))
+            result(Self.error(
+                .invalidBaseUrl,
+                "baseUrl must be an https:// origin with a host. Plain http:// is "
+                    + "accepted only for localhost while developing."
+            ))
             return
         }
         guard let presenter = Self.topViewController() else {
diff --git a/signosoft_signer/lib/src/channel.dart b/signosoft_signer/lib/src/channel.dart
index 6965e30..6bf5343 100644
--- a/signosoft_signer/lib/src/channel.dart
+++ b/signosoft_signer/lib/src/channel.dart
@@ -27,9 +27,13 @@ class SignerChannel {
   }) async {
     if (onDiagnostic != null) {
       _channel.setMethodCallHandler((call) async {
-        if (call.method == 'diagnostic') {
+        if (call.method != 'diagnostic') return;
+        // A host callback that throws must not surface as an unhandled async
+        // error attributed to the SDK. Diagnostics are a debugging aid; they
+        // cannot be allowed to affect the session.
+        try {
           onDiagnostic(parseDiagnostic(call.arguments));
-        }
+        } catch (_) {}
       });
     }
 
@@ -55,6 +59,11 @@ class SignerChannel {
         'The Signosoft signer plugin is not registered in this app. '
         'Rebuild the iOS app after adding the dependency.',
       );
+    } catch (error) {
+      // `open` is documented never to throw. Only PlatformException and
+      // MissingPluginException were actually caught, so a codec error or a
+      // malformed reply escaped into the caller's await and broke that promise.
+      return Failed(SignosoftErrorCode.unknown, 'The signer failed. $error');
     } finally {
       if (onDiagnostic != null) {
         _channel.setMethodCallHandler(null);
diff --git a/signosoft_signer/test/signer_test.dart b/signosoft_signer/test/signer_test.dart
index 925dd3e..1296396 100644
--- a/signosoft_signer/test/signer_test.dart
+++ b/signosoft_signer/test/signer_test.dart
@@ -142,6 +142,42 @@ void main() {
     expect((result as Failed).code, SignosoftErrorCode.unsupportedPlatform);
   });
 
+  test('an unexpected error still resolves to Failed, it does not throw', () async {
+    // Only PlatformException and MissingPluginException used to be caught, so
+    // anything else escaped into the caller's await — breaking the documented
+    // "Never throws" contract at the one place hosts were told to rely on it.
+    mockPlugin((call) async => throw StateError('something unforeseen'));
+
+    final result = await SignosoftSigner.open(
+      token: 'bioid-123',
+      baseUrl: _baseUrl,
+    );
+
+    expect((result as Failed).code, SignosoftErrorCode.unknown);
+    expect(result.message, contains('something unforeseen'));
+  });
+
+  test('a throwing onDiagnostic does not disturb the session', () async {
+    mockPlugin((call) async {
+      await messenger.handlePlatformMessage(
+        signosoftSignerChannel.name,
+        signosoftSignerChannel.codec.encodeMethodCall(
+          const MethodCall('diagnostic', {'event': 'ready', 'data': null}),
+        ),
+        (_) {},
+      );
+      return {'status': 'cancelled'};
+    });
+
+    final result = await SignosoftSigner.open(
+      token: 'bioid-123',
+      baseUrl: _baseUrl,
+      onDiagnostic: (_) => throw StateError('host callback blew up'),
+    );
+
+    expect(result, isA<Cancelled>());
+  });
+
   test('diagnostics are requested and delivered only when asked for', () async {
     final seen = <SignosoftDiagnostic>[];
 
```

---

## Appendix B — new files, in full

### `ios/Sources/SignosoftSigner/Model/ShellOrigin.swift`

```swift
import Foundation

/// The one origin the signer trusts: the one serving the shell.
///
/// Two jobs, both of which used to be missing. It decides whether a `baseUrl`
/// is loadable at all, and it decides whether a navigation or a bridge message
/// actually came from the shell rather than from something the shell navigated
/// to or embedded.
///
/// Deliberately free of WebKit so both can be tested off-device; the view
/// controller hands it the pieces of a `WKSecurityOrigin`.
struct ShellOrigin: Equatable, CustomStringConvertible {
    let scheme: String
    let host: String
    let port: Int

    var description: String { "\(scheme)://\(host):\(port)" }

    /// Nil when the URL has no scheme or no host — the same inputs
    /// `isUsable` rejects, minus the transport rule.
    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty
        else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = Self.effectivePort(url.port, scheme: scheme)
    }

    init(scheme: String, host: String, port: Int) {
        self.scheme = scheme.lowercased()
        self.host = host.lowercased()
        self.port = Self.effectivePort(port, scheme: scheme)
    }

    /// True when `other` is the same origin by scheme, host and port — the
    /// same comparison the web platform makes.
    func matches(_ other: ShellOrigin?) -> Bool { self == other }

    func matches(url: URL?) -> Bool {
        guard let url else { return false }
        return matches(ShellOrigin(url: url))
    }

    /// `WKSecurityOrigin.port` and `URL.port` both report 0/nil for the
    /// scheme's default, so they have to be normalised before comparing.
    private static func effectivePort(_ port: Int?, scheme: String) -> Int {
        if let port, port != 0 { return port }
        return scheme.lowercased() == "http" ? 80 : 443
    }

    /// Whether the signer can load this origin at all.
    ///
    /// Mirrors Android's `SignosoftSigner.isUsableBaseUrl`, so the same string
    /// is accepted or rejected identically on both platforms — and rejected up
    /// front with `invalidBaseUrl` rather than after a failed network load.
    ///
    /// Plain HTTP is only ever a locally served development shell. A public
    /// `http://` origin would put the bioid on the wire in cleartext, and the
    /// shell could not complete a signature over it anyway: such a page is not
    /// a secure context, so WebCrypto does not exist there.
    static func isUsable(_ url: URL) -> Bool {
        guard let origin = ShellOrigin(url: url) else { return false }
        return origin.scheme == "https"
            || (origin.scheme == "http" && isLoopbackHost(origin.host))
    }

    /// `10.0.2.2` is the Android emulator's route to the host machine, and is
    /// accepted here too so one baseUrl behaves the same on both platforms.
    static func isLoopbackHost(_ host: String) -> Bool {
        switch host {
        case "localhost", "127.0.0.1", "::1", "[::1]", "10.0.2.2": return true
        default: return host.hasSuffix(".localhost")
        }
    }
}
```

### `ios/Tests/SignosoftSignerTests/ShellOriginTests.swift`

```swift
import XCTest

@testable import SignosoftSigner

final class ShellOriginTests: XCTestCase {

    // MARK: - isUsable

    func testAcceptsHttpsOrigins() {
        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "https://www.signosoft.com/mobilesdk/")!))
        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "https://tenant.example.com")!))
        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "https://example.com:8443/shell")!))
    }

    /// The old behaviour: `URL(string:)` accepts these, so the ceremony opened,
    /// failed to load, and reported `loadFailed` seconds later.
    func testRejectsInputWithNoSchemeOrNoHost() {
        XCTAssertFalse(ShellOrigin.isUsable(URL(string: "notaurl")!))
        XCTAssertFalse(ShellOrigin.isUsable(URL(string: "/just/a/path")!))
        XCTAssertFalse(ShellOrigin.isUsable(URL(string: "file:///tmp/shell.html")!))
    }

    /// A public cleartext origin would put the bioid on the wire, and could not
    /// complete a signature anyway — no secure context, no WebCrypto.
    func testRejectsPublicCleartextButAllowsLoopback() {
        XCTAssertFalse(ShellOrigin.isUsable(URL(string: "http://shell.example.com")!))
        XCTAssertFalse(ShellOrigin.isUsable(URL(string: "http://192.168.1.20:4200")!))

        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "http://localhost:4200")!))
        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "http://127.0.0.1:4200")!))
        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "http://10.0.2.2:4200")!))
    }

    // MARK: - matches

    func testMatchesIsCaseInsensitiveAndPortAware() {
        let shell = ShellOrigin(url: URL(string: "https://www.signosoft.com/mobilesdk/")!)

        XCTAssertTrue(shell!.matches(url: URL(string: "https://WWW.Signosoft.COM/other/page")!))
        // 443 is https's default, however it is spelled.
        XCTAssertTrue(shell!.matches(url: URL(string: "https://www.signosoft.com:443/x")!))

        XCTAssertFalse(shell!.matches(url: URL(string: "https://evil.example.com/")!))
        XCTAssertFalse(shell!.matches(url: URL(string: "http://www.signosoft.com/")!))
        XCTAssertFalse(shell!.matches(url: URL(string: "https://www.signosoft.com:8443/")!))
        // A subdomain is a different origin.
        XCTAssertFalse(shell!.matches(url: URL(string: "https://a.www.signosoft.com/")!))
        XCTAssertFalse(shell!.matches(url: nil))
    }

    /// `WKSecurityOrigin` reports 0 for a scheme's default port; `URL` reports
    /// nil. They have to compare equal.
    func testDefaultPortFromWebKitMatchesDefaultPortFromURL() {
        let shell = ShellOrigin(url: URL(string: "https://www.signosoft.com/")!)
        let fromWebKit = ShellOrigin(scheme: "https", host: "www.signosoft.com", port: 0)

        XCTAssertTrue(shell!.matches(fromWebKit))
    }

    func testExplicitPortIsCompared() {
        let shell = ShellOrigin(url: URL(string: "http://localhost:4200/")!)

        XCTAssertTrue(shell!.matches(ShellOrigin(scheme: "http", host: "localhost", port: 4200)))
        XCTAssertFalse(shell!.matches(ShellOrigin(scheme: "http", host: "localhost", port: 4201)))
        // Default-port normalisation must not swallow an explicit mismatch.
        XCTAssertFalse(shell!.matches(ShellOrigin(scheme: "http", host: "localhost", port: 0)))
    }
}
```
