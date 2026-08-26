/// Supplied at run time so no live token is committed:
///
///   `flutter run --dart-define=BIOID=<token>`
///
/// `BASE_URL` defaults to the hosted shell and only needs passing to override
/// it.
///
/// A real integrator fetches the bioid from their own backend at the moment
/// they need it. This demo reads it from the environment because it has no
/// backend of its own — never ship a hardcoded token.
const kBioId = String.fromEnvironment('BIOID');

/// Origin serving the Signosoft signing shell. Defaults to the hosted one, so
/// only `BIOID` has to be passed; override for a tenant-specific origin or a
/// locally served build of the shell.
const kEmbeddedBaseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'https://www.signosoft.com/mobilesdk/',
);

const kIsConfigured = kBioId != '' && kEmbeddedBaseUrl != '';

const kReportAsset = 'assets/mock-medical-report.pdf';
