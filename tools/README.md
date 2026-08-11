# tools

Internal. `mint-bioid.mjs` talks to the Signosoft API with **your own**
credentials; it is not something a customer can run, and it is not part of the
published SDK.

## mint-bioid

Prints a fresh `bioid` — a document-link token you can hand to
`SignosoftSigner.open()`:

```bash
node tools/mint-bioid.mjs
```

Progress goes to stderr, the token alone to stdout, so it composes:

```bash
cd examples/medicly
flutter run -d <device id> --dart-define=BIOID=$(node ../../tools/mint-bioid.mjs)
```

Add `--dart-define=BASE_URL=<origin>` to point at something other than the hosted
shell; `flutter devices` prints device ids.

### What it does

The same four calls the web app makes when a user uploads a PDF and sends it for
signature:

| Call | Result |
|---|---|
| `REST/uploadDocument` | uploads `examples/medicly/assets/mock-medical-report.pdf`; returns `docid` + `doctoken` |
| `REST/saveSignatures` | places two fields: `simple` (typed) and `biometric` (*Handwritten* in the UI) |
| `REST/createSignRequest` | moves the document to *ready to sign* |
| `REST/createDocLink` | **the `bioid`** |

Each run creates a real document and spends a sign request. A token is consumed
by signing or rejecting; opening and cancelling leaves it usable, so one token
survives many attempts.

### Configuration

`tools/.mint-bioid.env` — gitignored, copy from `.mint-bioid.env.example`:

| Key | Value in the test environment |
|---|---|
| `SIGNOSOFT_API` | `https://api-test.signosoft.com` |
| `SIGNOSOFT_AUTH` | `https://auth-preprod.signosoft.com` |
| `SIGNOSOFT_REALM` | `test` — **not** `signosoft`, which the frontend env files claim and which does not exist |
| `SIGNOSOFT_CLIENT_ID` | `app-dev` — the only client there with direct access grants enabled |
| `SIGNOSOFT_USER` / `_PASSWORD` | your Keycloak login. The username may differ from your work email — it is whatever `preferred_username` says in an access token from the web app |

### Field placement

`FIELDS` at the top of the script. **Coordinates are percentages of the page**,
top-left origin, page 1. Not a guess: a field placed by hand in the web app comes
back from `getUserDocuments` as
`{"page":1,"x":55.87,"y":51.54,"w":17.19,"h":6.66}`. Send PDF points instead and
the field lands off the page — the server then renders it on a page of its own,
which looks exactly like "the signatures are on separate pages".

### When it fails

| Symptom | Meaning |
|---|---|
| `HTTP 502` (or any 5xx) from the token endpoint | the auth server is down, not your credentials. `curl -o /dev/null -w '%{http_code}\n' https://auth-preprod.signosoft.com/realms/test/.well-known/openid-configuration` — 5xx means wait |
| `invalid_grant: Invalid user credentials` | wrong realm, or the username is not what you assume. Decode a token from the web app and read `preferred_username` / `iss` |
| `unauthorized_client: Client not allowed for direct access grants` | that client cannot do password grants — use `app-dev` |
| `createDocLink gave no bioid` | the raw JSON is printed; the response shape changed |
| The ceremony opens but never becomes ready, then `loadTimeout` after 45s | not the SDK. Open `<shell>/?bioid=<token>` in a desktop browser and read the console |

Check a token by hand, without the SDK:

```bash
curl -s -X POST https://api-test.signosoft.com/openDocLink \
  --data-urlencode "docLink=<bioid>" | python3 -m json.tool | head -40
```

`openDocLinkResult: OK` plus a `docObject.signatures` array means the document and
its fields are fine, and any failure after that is client- or shell-side.

## Testing against a locally built shell

In the frontend repo:

```bash
npx nx build embedded -c test
npx http-server dist/apps/embedded/browser -p 4204 -a 0.0.0.0 --proxy "http://127.0.0.1:4204?" --cors
```

Then point the app at an address the device can actually reach:

```bash
cd examples/medicly
flutter run -d <device id> \
  --dart-define=BIOID=$(node ../../tools/mint-bioid.mjs) \
  --dart-define=BASE_URL=http://$(ipconfig getifaddr en7):4204
```

**Use the right interface.** A USB-tethered iPad reaches the Mac on a link-local
address on `en7` (`169.254.x.x`), not the Wi-Fi address on `en0` — and it changes
when the iPad reconnects. Point the app at an address the device cannot reach and
the WebView never connects: no page, no bridge event, `loadTimeout` after 45s,
indistinguishable from a broken shell. The server's access log settles it — a
request from the iPad means it got through.

Cleartext to a private address loads fine — Medicly's `Info.plist` carries
`NSAllowsLocalNetworking` — but **a signature cannot be completed over it**. The
shell encrypts biometric data with WebCrypto, and `crypto.subtle` only exists in a
secure context: HTTPS, or `localhost`. Over `http://169.254.x.x` the ceremony
renders and then fails with `undefined is not an object (evaluating
'crypto.subtle.importKey')`.

So: use `http://localhost:4204` on a **simulator** to test signing locally, and
HTTPS (the deployed shell) on a **physical device**. A plain-HTTP LAN address is
only good for testing that the shell loads and reaches `ready`.

The `wss://localhost:8111/SignoSoftDriver/echo` error alongside it is the local
signature-pad driver, which does not exist on iPadOS. Harmless.
