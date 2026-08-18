# Getting started — one page

For the developer who has just been handed the Signosoft Mobile SDK.

## What this does

Your app calls one method with a token. A full-screen signature ceremony
appears. The patient signs. You get a typed result and a way to fetch the signed
PDF. Everything happens inside your app.

**iOS and iPadOS only.** There is no Android implementation in this release — on
Android `open()` resolves to `Failed(unsupportedPlatform)` and nothing appears.
Before you plan a signature method, read
[Known limitations](INTEGRATION.md#known-limitations): handwritten
signature-pad fields cannot be completed from the hosted shell's origin today,
and a typed field's *Draw* tab is the way to take a finger-drawn signature.

## What a `bioid` is

A `bioid` is a **single-use document link token** identifying one document, one
signer, one signing session. Treat it as an opaque string: the SDK only checks
that it is non-empty, and nothing on either side validates its length or shape,
so do not build a format check of your own.

- **Your backend mints it**, by calling the Signosoft REST API `createDocLink`
  with your Signosoft credentials. The SDK cannot create one and neither can
  your app.
- It is **consumed by a terminal outcome.** Completing the signature or
  rejecting the document uses it up. Opening and cancelling does not.
- Treat it as a **secret**. Anyone holding it can sign that document. Fetch it
  from your backend at the moment you need it; do not cache it, log it, or put
  it in analytics.

```
Your backend ──createDocLink──► Signosoft ──bioid──► your app ──► SignosoftSigner.open()
```

## What you need from Signosoft before you start

| Thing | Why | Who gives it to you |
|---|---|---|
| Read access to `github.com/signosoft/signosoft-mobile-sdk` | the SDK installs as a `git:` dependency from a private repo | Signosoft |
| API credentials for `createDocLink` / `downloadDoc` | your backend mints tokens and fetches signed PDFs | Signosoft |
| The **shell URL** for `baseUrl` | the SDK loads the signing UI from it | already known: `https://www.signosoft.com/mobilesdk/` |
| A test `bioid` or two | to run the flow before wiring your backend | Signosoft |
| Tenant configuration | which signature methods appear, whether *Reject* is offered | Signosoft |

> **`baseUrl` is `https://www.signosoft.com/mobilesdk/`.** That host serves the
> signing shell today; `<host>/?bioid=<token>` renders the ceremony. The
> parameter is still required — pass the URL explicitly — so a tenant on its own
> origin only changes one argument.

## Five-minute integration

1. Deployment target **iOS 16.0**; Flutter **3.44** or newer.
2. Add the dependency (see the [README](../README.md#install)).
3. Add the `Info.plist` keys from
   [INTEGRATION.md](INTEGRATION.md#2-host-infoplist).
4. Fetch a `bioid` from your backend.
5. Call `SignosoftSigner.open(token: bioid, baseUrl: ...)` and switch on the
   four outcomes.
6. On `Signed`, send `documentToken` to your backend and have it call
   `downloadDoc`.

Two runnable versions ship with the SDK:

- `examples/medicly/` — a realistic host app: patient, report, Sign button, the
  signed PDF rendered on return. It adapts to the window width, so it runs on
  iPhone as well as iPad. Start here.
- `signosoft_signer/example/` — the bare minimum: two text fields and the four
  outcomes, with nothing else in the way.

## The four outcomes, in one table

| Outcome | Server state | What you do |
|---|---|---|
| `Signed` | signed, recorded | fetch the PDF with `documentToken`, attach it to the record |
| `Rejected` | rejected, terminal | record the refusal; this `bioid` is dead |
| `Cancelled` | unchanged | offer to try again with the same `bioid` |
| `Failed` | usually unchanged | branch on `code`; see the troubleshooting table |

## Reporting a bug

**info@signosoft.com**, with:

- the `SignosoftErrorCode` and message, or the outcome you got and expected
- the `documentToken` (safe to share — unlike the `bioid`)
- the diagnostic log: pass `onDiagnostic` to `open()` and include what it printed
- iOS version, device or simulator model, Flutter version

## Where to go next

[INTEGRATION.md](INTEGRATION.md) — the complete guide, including a
troubleshooting table built from failures we actually hit.
