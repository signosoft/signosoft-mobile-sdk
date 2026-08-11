# signosoft_signer

Flutter binding for the Signosoft Mobile SDK. Opens the Signosoft signature
ceremony inside your app and returns a typed result. **iOS only** in this phase.

Full guide — install, `Info.plist`, App Transport Security, outcomes,
troubleshooting: [`../docs/INTEGRATION.md`](../docs/INTEGRATION.md).
New to the SDK: [`../docs/GETTING-STARTED.md`](../docs/GETTING-STARTED.md).

```dart
final result = await SignosoftSigner.open(
  token: bioid,
  baseUrl: Uri.parse('https://www.signosoft.com/mobilesdk/'),
);

switch (result) {
  case Signed(:final documentToken, :final signedPdfPath):
  case Rejected(:final documentToken):
  case Cancelled():
  case Failed(:final code, :final message):
}
```

`open()` never throws — every failure is a `Failed` carrying a
`SignosoftErrorCode` you can branch on.

`signedPdfPath` may be null; the signature is still valid. `downloadUrl` is
always null in this version — have your backend call `downloadDoc` with
`documentToken`.

This package must stay next to the `ios/` Swift core it ships with; it reaches
it through a relative symlink. See
[why both packages ship together](../docs/INTEGRATION.md#3-installing-and-why-both-packages-ship-together).

## Example

`example/` is a minimal integration: a token field, a base URL field, a Sign
button, and all four outcomes rendered with what to do about each.

```bash
cd example
flutter run -d "iPad Pro 13-inch (M5)"
```

## Tests

```bash
flutter test
```
