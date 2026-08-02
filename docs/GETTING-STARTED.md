# Getting started — one page

For the developer who has just been handed the Signosoft Mobile SDK.

## What this does

Your app calls one method with a token. A full-screen signature ceremony
appears. The patient signs. You get a typed result and a way to fetch the signed
PDF. Everything happens inside your app.

## What a `bioid` is

A `bioid` is a **single-use document link token**: a 64-character hex string that
identifies one document, one signer, one signing session.

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
| The **shell URL** for `baseUrl` | the SDK loads the signing UI from it | Signosoft — see the note below |
| A test `bioid` or two | to run the flow before wiring your backend | Signosoft |
| Tenant configuration | which signature methods appear, whether *Reject* is offered | Signosoft |

> **`baseUrl` has no default yet.** The hosted signing shell is being stood up;
> until Signosoft gives you a URL, `baseUrl` is a required parameter and there is
> nothing sensible to put in it. Ask for it before you plan your integration
> milestones. When the hosted URL lands, `baseUrl` becomes optional and the
> parameter stays source-compatible.

## Five-minute integration

1. Deployment target **iOS 16.0** / **Android API 24**; Flutter **3.44** or
   newer.
2. Add the dependency (see the [README](../README.md#install)).
3. Add the `Info.plist` keys and Android manifest permissions from
   [INTEGRATION.md](INTEGRATION.md#2-host-permissions).
4. Fetch a `bioid` from your backend.
5. Call `SignosoftSigner.open(token: bioid, baseUrl: ...)` and switch on the
   four outcomes.
6. On `Signed`, send `documentToken` to your backend and have it call
   `downloadDoc`.

Two runnable versions ship with the SDK:

- `examples/medicly/` — a realistic tablet host app: patient, report, Sign
  button, the signed PDF rendered on return. Builds for iOS and Android. Start
  here.
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
- iOS or Android version, device / simulator / emulator model, Flutter version

## Where to go next

[INTEGRATION.md](INTEGRATION.md) — the complete guide, including a
troubleshooting table built from failures we actually hit.
