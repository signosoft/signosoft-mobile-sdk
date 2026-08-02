---
name: Bug report
about: Something in the SDK did not behave as documented
---

**Never paste a `bioid` here.** It is a secret — anyone holding it can sign that
document. `documentToken` is safe to share.

## What happened

<!-- The outcome you got and the outcome you expected. -->

## The error code

<!-- The `SignosoftErrorCode` from `Failed`, the Swift `SignosoftError.code`, or
     the Kotlin `SignosoftSignerResult.Failed.code`. The message is for
     developers and its wording changes; the code does not. -->

## Diagnostics

<!-- Pass onDiagnostic to open() and paste what it printed:

     await SignosoftSigner.open(
       token: bioid,
       baseUrl: shell,
       onDiagnostic: (d) => log('signosoft: ${d.event} ${d.data ?? ''}'),
     );
-->

```
```

## Environment

- SDK version:
- Flutter / Dart version (`flutter --version`):
- Platform (iOS / Android):
- Xcode version, or Android Gradle plugin and JDK version:
- OS version, and device / simulator / emulator model:
- `documentToken`, if you got one:
