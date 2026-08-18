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

## One `bioid` authorises one signature

If a document has several signature fields, your backend must mint **one `bioid`
per field**, and your app must run **one `open()` per field**. A single token
cannot complete a multi-field document: the first field signs, and every
remaining field is then refused with that token — including after closing and
reopening the ceremony. A client who mints one token for a two-field document
never receives a terminal outcome at all.

This constrains how your *backend* mints tokens, which is why it sits here rather
than in a troubleshooting table.

**How well we know this.** Observed three times on 2026-08-18 against the test
tenant, with each document's server-side signature state read back from
`openDocLink` afterwards. It **contradicts one internal recollection** of a single
token signing two fields, and that contradiction is not resolved. Design for one
token per signature; if your flow needs one signer to fill several fields with
one token, ask Signosoft to confirm it before you build on it.

Separately — and *not* the cause of the above — the ceremony offers no *Finalize*
action, and the test tenant reports `allowPartialFinalize: false`, so a document
left partly signed cannot be submitted from inside the ceremony either. See
[INTEGRATION.md §5](INTEGRATION.md#5-the-four-outcomes).

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

1. Deployment target **iOS 16.0**; Flutter **3.44** or newer. A stock Flutter
   project ships **13.0** in three places and has no `Podfile` — see
   [INTEGRATION.md §1](INTEGRATION.md#1-requirements) for exactly what to change.
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
- iOS version, device or simulator model, Flutter version

## Where to go next

[INTEGRATION.md](INTEGRATION.md) — the complete guide, including a
troubleshooting table built from failures we actually hit.
