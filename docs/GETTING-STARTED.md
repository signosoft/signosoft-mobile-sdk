# Getting started — one page

For the developer who has just been handed the Signosoft Mobile SDK.

## What this does

Your app calls one method with a token. A full-screen signature ceremony
appears. The patient signs. You get a typed result and a way to fetch the signed
PDF. Everything happens inside your app.

**iOS, iPadOS and Android.** Both platforms are verified on a simulator or
emulator only — no run on physical hardware has happened yet. Before you plan a
signature method, read
[Known limitations](INTEGRATION.md#known-limitations): handwritten
signature-pad fields cannot be completed from the hosted shell's origin today,
and a typed field's *Draw* tab is the way to take a finger-drawn signature.

## What a `bioid` is

A `bioid` is a **document-link token** identifying one document, one signer, one
signing session. Treat it as an opaque string: the SDK only checks that it is
non-empty, and nothing on either side validates its length or shape, so do not
build a format check of your own.

- **Your backend mints it**, by calling the Signosoft REST API `createDocLink`
  with your Signosoft credentials. The SDK cannot create one and neither can
  your app.
- It is **consumed by a terminal outcome.** Completing the signature or
  rejecting the document uses it up. Opening and cancelling does not — the same
  token opens again.
- **A consumed token does not start failing.** Reopening a `bioid` whose
  signature has already completed renders the *finished* document, read-only,
  with its signature block on it; closing that reports `Cancelled`, not
  `sessionFailed`. Never use the outcome of `open()` to decide whether a token is
  still usable — ask your backend for the document's signature state.
- Treat it as a **secret**. Anyone holding it can sign that document. Fetch it
  from your backend at the moment you need it; do not cache it, log it, or put
  it in analytics.

```
Your backend ──createDocLink──► Signosoft ──bioid──► your app ──► SignosoftSigner.open()
```

## One `bioid` per document

One token covers one document and one signer. Your backend mints it for that
document, the signer completes the document with it, and a terminal outcome —
signing or rejecting — uses it up. Opening and closing the ceremony does not.

Give each document a **single signature field**. That is the shape this release is
built and tested around, and it is what the reference app uses.

## What you need from Signosoft before you start

| Thing | Why | Who gives it to you |
|---|---|---|
| API credentials for `createDocLink` / `downloadDoc` | your backend mints tokens and fetches signed PDFs | Signosoft |
| The **shell URL** for `baseUrl` | the SDK loads the signing UI from it | already known: `https://www.signosoft.com/mobilesdk/` |
| A test `bioid` or two | to run the flow before wiring your backend | Signosoft |
| Tenant configuration | which signature methods appear, and whether a *Reject* control is rendered | Signosoft |

The SDK itself needs nothing from Signosoft to install: the repository is public
over HTTPS and `flutter pub get` needs no credentials.

> **`baseUrl` is `https://www.signosoft.com/mobilesdk/`.** That host serves the
> signing shell today; `<host>/?bioid=<token>` renders the ceremony. The
> parameter is still required — pass the URL explicitly — so a tenant on its own
> origin only changes one argument.
>
> It must be an `https://` origin with a host. Plain `http://` is accepted only
> for `localhost`, `*.localhost`, `127.0.0.1`, `::1` and `10.0.2.2` while
> developing. Anything else returns `Failed(invalidBaseUrl)` immediately, before
> the signer appears — a public `http://` origin is rejected outright, and could
> not complete a signature anyway: it is not a secure context, so WebCrypto does
> not exist there.

## Five-minute integration

1. Deployment target **iOS 16.0**, or Android **`minSdk` 24**; Flutter **3.44**
   or newer. A stock Flutter project ships iOS **13.0** in three places and has
   no `Podfile`, and `minSdk` 21 in `app/build.gradle.kts` — see
   [INTEGRATION.md §1](INTEGRATION.md#1-requirements) for exactly what to change.
2. Add the dependency (see the [README](../README.md#install)).
3. Add the `Info.plist` keys, or the Android manifest permissions, from
   [INTEGRATION.md](INTEGRATION.md#2-host-permissions).
4. Fetch a `bioid` from your backend.
5. Call `SignosoftSigner.open(token: bioid, baseUrl: ...)` and switch on the
   four outcomes.
6. On `Signed`, send `documentToken` to your backend and have it call
   `downloadDoc`.

Two runnable versions ship with the SDK:

- `examples/medicly/` — a realistic host app: patient, report, Sign button, the
  signed PDF rendered on return. It adapts to the window width, so it runs on
  iPhone as well as iPad, and on Android. Start here.
- `signosoft_signer/example/` — the bare minimum: two text fields and the four
  outcomes, with nothing else in the way.

## The four outcomes, in one table

| Outcome | Server state | What you do |
|---|---|---|
| `Signed` | signed, recorded | fetch the PDF with `documentToken`, attach it to the record |
| `Rejected` | rejected, terminal | record the refusal; this `bioid` is dead. Whether a *Reject* control is offered at all is tenant configuration — ask Signosoft about yours |
| `Cancelled` | **not necessarily unchanged** | you may reopen the same `bioid`, but re-read the document's state rather than assume nothing was recorded |
| `Failed` | usually unchanged | branch on `code`; see the troubleshooting table |

## Reporting a bug

**info@signosoft.com**, with:

- the `SignosoftErrorCode` and message, or the outcome you got and expected. The
  SDK redacts the `bioid` from its own messages, so a message is safe to send —
  but check anything you have added around it
- the `documentToken` (safe to share — unlike the `bioid`)
- the diagnostic log: pass `onDiagnostic` to `open()` and include what it printed
- iOS or Android version, device / simulator / emulator model, Flutter version

## Where to go next

[INTEGRATION.md](INTEGRATION.md) — the complete guide, including a
troubleshooting table built from failures we actually hit.
