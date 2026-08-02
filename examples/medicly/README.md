# Medicly — a realistic host app for the Signosoft Mobile SDK

A Flutter iPad app standing in for a medical customer. It shows a patient, renders a
mock medical report, and has a **Sign document** button that opens the real Signosoft
signature ceremony. On `Signed` the viewer swaps to the signed PDF the ceremony
returned and the status chip reflects signed / rejected / cancelled / failed.

This is the reference integration. The whole SDK usage is one import and one call in
[`lib/report_screen.dart`](lib/report_screen.dart); everything else is ordinary app code.

```yaml
# pubspec.yaml — this example is inside the distribution, so it uses a path.
# Your app uses the git: dependency from ../../README.md instead.
signosoft_signer:
  path: ../../signosoft_signer
```

## Run it

The token and the shell origin are **not committed** — pass them at run time:

```bash
flutter run -d "iPad Pro 13-inch (M5)" \
  --dart-define=BIOID=<your bioid> \
  --dart-define=BASE_URL=<the shell origin Signosoft gave you>
```

Without both defines the Sign button stays disabled and says so. `flutter devices`
lists what is booted; any iPad simulator works.

Your backend mints the `bioid` with `createDocLink` — see
[GETTING-STARTED.md](../../docs/GETTING-STARTED.md). One token buys one terminal
outcome: signing or rejecting consumes it, opening and cancelling does not.

## What the host app has to provide

`ios/Runner/Info.plist` carries the camera / microphone / photo / local-network usage
strings and, for a plain-HTTP `BASE_URL`, the App Transport Security exception. **The
SDK cannot declare those for its host** — iOS attributes them to the app that ships.
That is exactly the situation your app is in; see
[INTEGRATION.md §2](../../docs/INTEGRATION.md#2-host-infoplist).

## Open in Xcode

Run `flutter run` **once first** — it generates `ios/Flutter/Generated.xcconfig`.
Opening Xcode before that fails with a missing-file error. Then open
`ios/Runner.xcworkspace` (the workspace, not `Runner.xcodeproj`), scheme **Runner**,
destination an iPad simulator.

Physical iPad: target **Runner** → **Signing & Capabilities** → set your Team, and
change the bundle id if `com.signosoft.mediclyDemo` collides in your account.

## Layout

| File | Role |
|---|---|
| `lib/main.dart` | App entry + theme |
| `lib/config.dart` | Reads `BIOID` and `BASE_URL` from the environment |
| `lib/report_screen.dart` | Whole UI; calls `SignosoftSigner.open` and reflects the outcome |
| `lib/medicly_logo.dart` | Painted logo + brand colours |
| `assets/mock-medical-report.pdf` | The document being signed |

PDF rendering uses [`pdfrx`](https://pub.dev/packages/pdfrx) (PDFium). That is a
demo-app dependency only — the SDK itself does not need it.
