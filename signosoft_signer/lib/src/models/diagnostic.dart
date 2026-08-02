import 'package:flutter/foundation.dart';

/// A raw bridge message observed during a signing session.
///
/// Diagnostics exist to debug an integration. They are **not** API: event
/// names, payload shapes and ordering may change in any release. Never branch
/// product behaviour on them — switch on the sign result instead.
@immutable
class SignosoftDiagnostic {
  const SignosoftDiagnostic({required this.event, this.data});

  /// Bridge event name, e.g. `ready`, `signed`, `rejected`, `error`.
  final String event;

  /// Payload the shell sent with the event. The native side elides the signed
  /// PDF bytes, so this stays cheap enough to log.
  final Map<String, Object?>? data;

  @override
  String toString() => 'SignosoftDiagnostic($event, $data)';
}
