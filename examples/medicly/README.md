# Medicly — a realistic host app for the Signosoft Mobile SDK

A Flutter app standing in for a medical customer. It shows a patient, renders a
mock medical report, and has a **Sign document** button that opens the real Signosoft
signature ceremony. On `Signed` the viewer swaps to the signed PDF the ceremony
returned and the status chip reflects signed / rejected / cancelled / failed.

It runs on **iPhone and iPad**. The layout follows Material's window width
classes, all of which live in
[`lib/report_screen.dart`](lib/report_screen.dart):

| Window width | Layout | Pinned text scale |
|---|---|---|
| ≥ 900pt (iPad full screen) | side panel beside the document, Sign button in the panel | 2.0 |
| 600–900pt (iPad split view) | panel stacked above the document, Sign button pinned at the bottom | 1.5 |
| < 600pt (iPhone) | same stacked layout, smaller toolbar, avatar-only clinician chip, document opens fit-to-width | 1.15 |

Text scaling is pinned rather than taken from the reader's setting, because the
demo is meant to be legible from across a room. The iPad appearance at 2x is the
reference; the phone steps down because 2x does not fit. That is demo styling,
not something the SDK does or asks of you.

This is the reference integration. The whole SDK usage is one import and one call in
[`lib/report_screen.dart`](lib/report_screen.dart); everything else is ordinary app code.

```yaml
# pubspec.yaml — this example is inside the distribution, so it uses a path.
# Your app uses the git: dependency from ../../README.md instead.
signosoft_signer:
  path: ../../signosoft_signer
```

## Run it

No token is committed — pass one at run time:

```bash
flutter run -d "iPad Pro 13-inch (M5)" --dart-define=BIOID=<your bioid>
```

`BASE_URL` defaults to the hosted shell, `https://www.signosoft.com/mobilesdk/`;
add `--dart-define=BASE_URL=<origin>` only to point at a tenant-specific origin
or a locally served build. Without `BIOID` the Sign button stays disabled and
says so. `flutter devices` lists what is booted; any iOS simulator works —
iPhone as well as iPad:

```bash
flutter run -d "iPhone 17" --dart-define=BIOID=<your bioid>
```

### Running on a physical iPhone or iPad

Pass the device id from `flutter devices` — the physical device is the line
*without* `(simulator)` on it. A simulator often carries the same product name as
the phone in your hand, so match on the id, not the name.

```bash
flutter run -d <device id> --dart-define=BIOID=<your bioid>
```

The first install of a build signed with a personal or development team stops at
**"Untrusted Developer"** on the device, and `flutter run` hangs at *Installing
and launching*. iOS will not run it until you trust the certificate **on the
device**:

1. Settings → **General → VPN & Device Management**
2. Under *Developer App*, tap your signing identity
   (`Apple Development: <your Apple ID>`)
3. **Trust** → confirm

Then rerun `flutter run`. The trust is per certificate, not per app, so it
survives later builds until the certificate changes.

If *VPN & Device Management* has no *Developer App* section, turn on Settings →
**Privacy & Security → Developer Mode**, reboot, and confirm after unlocking.
That toggle only appears once a development-signed app has been installed at
least once.

Your backend mints the `bioid` with `createDocLink` — see
[GETTING-STARTED.md](../../docs/GETTING-STARTED.md). One token buys one terminal
outcome: signing or rejecting consumes it, opening and cancelling does not. It
also authorises exactly **one signature**, which is why this demo's document has a
single field — a multi-field document needs one token per field.

Signosoft developers can skip the backend entirely: `tools/mint-bioid.mjs` mints a
document and prints its `bioid` — see [tools/README.md](../../tools/README.md).

```bash
flutter run -d <device id> --dart-define=BIOID=$(node ../../tools/mint-bioid.mjs)
```

## What the host app has to provide

`ios/Runner/Info.plist` carries the camera / microphone / photo / local-network usage
strings and, for a locally served plain-HTTP `BASE_URL`, the App Transport Security
exception. **The
SDK cannot declare those for its host** — iOS attributes them to the app that ships.
That is exactly the situation your app is in; see
[INTEGRATION.md §2](../../docs/INTEGRATION.md#2-host-infoplist).

## Open in Xcode

Run `flutter run` **once first** — it generates `ios/Flutter/Generated.xcconfig`.
Opening Xcode before that fails with a missing-file error. Then open
`ios/Runner.xcworkspace` (the workspace, not `Runner.xcodeproj`), scheme **Runner**,
destination any iOS simulator.

Physical device: target **Runner** → **Signing & Capabilities** → set your Team, and
change the bundle id if `com.signosoft.mediclyDemo` collides in your account.

## What the demo does not show

The report is minted with **one typed signature field**, and it signs — the demo
reaches `Signed` and renders the signed PDF that comes back.

It is deliberately one field, for two reasons.

**One `bioid` authorises one signature.** A document with several fields needs one
token and one `open()` per field; on a single token the first field signs and the
rest are refused, so a two-field demo could never reach a terminal outcome. See
[GETTING-STARTED.md](../../docs/GETTING-STARTED.md#one-bioid-authorises-one-signature).

**The handwritten (signature-pad) field cannot be completed** from this shell's
origin at all: it opens, the pad reports *"Connection error."*, and *Confirm
Signature* never enables. That is a server-side signature-pad licence that does
not list the origin — not the SDK, and not this demo. Full explanation and the two
remedies:
[INTEGRATION.md § Known limitations](../../docs/INTEGRATION.md#known-limitations).

To take a finger-drawn signature, use the typed field's **Draw** tab.

## Tests

```bash
flutter test
```

Six widget tests over the layout: no overflow at phone or tablet size, the Sign
button reachable at both, the disabled-button explanation when `BIOID` is
missing, and the text scale stepping down with the width class. They are what
keeps a phone-width regression from being invisible on an iPad.

## Layout

| File | Role |
|---|---|
| `lib/main.dart` | App entry + theme; pins the demo text scale to the width class |
| `lib/config.dart` | Reads `BIOID` and `BASE_URL` from the environment |
| `lib/report_screen.dart` | Whole UI; width classes; calls `SignosoftSigner.open` and reflects the outcome |
| `lib/medicly_logo.dart` | Painted logo + brand colours |
| `test/report_screen_test.dart` | The six layout tests above |
| `assets/mock-medical-report.pdf` | The document being signed |

PDF rendering uses [`pdfrx`](https://pub.dev/packages/pdfrx) (PDFium). That is a
demo-app dependency only — the SDK itself does not need it.
