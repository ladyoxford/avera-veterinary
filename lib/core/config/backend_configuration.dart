class BackendConfiguration {
  const BackendConfiguration._();

  static const apiBaseUrl = String.fromEnvironment('AVERA_API_BASE_URL');
  static const enableLocalDevelopmentAuth = bool.fromEnvironment(
    'ENABLE_LOCAL_DEVELOPMENT_AUTH',
    defaultValue: true,
  );

  static bool get isRemoteBackendConfigured => apiBaseUrl.isNotEmpty;

  static void validateProductionConfiguration({required bool isProduction}) {
    if (isProduction && enableLocalDevelopmentAuth) {
      throw StateError(
        'Production builds cannot enable local development authentication.',
      );
    }
  }
}
