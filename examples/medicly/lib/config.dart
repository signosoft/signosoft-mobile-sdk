/// Supplied at run time so no live token or host is committed:
///
///   `flutter run --dart-define=BIOID=<token> --dart-define=BASE_URL=<origin>`
///
/// A real integrator fetches the bioid from their own backend at the moment
/// they need it. This demo reads it from the environment because it has no
/// backend of its own — never ship a hardcoded token.
const kBioId = String.fromEnvironment('BIOID');

/// Origin serving the Signosoft signing shell. Ask Signosoft for yours.
const kEmbeddedBaseUrl = String.fromEnvironment('BASE_URL');

const kIsConfigured = kBioId != '' && kEmbeddedBaseUrl != '';

const kReportAsset = 'assets/mock-medical-report.pdf';
