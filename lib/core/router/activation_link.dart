const clinicAdministratorActivationPath = '/activate-clinic-admin';
const clinicAdministratorActivationHost = 'accounts.averavet.sbs';

String? clinicAdministratorActivationToken(Uri uri) {
  if (uri.path != clinicAdministratorActivationPath) return null;

  final isInternalRoute = uri.scheme.isEmpty && uri.host.isEmpty;
  final isVerifiedHttps =
      uri.scheme == 'https' && uri.host == clinicAdministratorActivationHost;
  final isAveraFallback = uri.scheme == 'avera' && uri.host == 'app';
  if (!isInternalRoute && !isVerifiedHttps && !isAveraFallback) return null;

  final token = uri.queryParameters['token']?.trim();
  return token == null || token.isEmpty ? null : token;
}
