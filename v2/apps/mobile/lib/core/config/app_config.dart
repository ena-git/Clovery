abstract final class AppConfig {
  static const environment = String.fromEnvironment(
    'CLOVERY_ENV',
    defaultValue: 'development',
  );

  static const apiBaseUrl = String.fromEnvironment(
    'CLOVERY_API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
}
