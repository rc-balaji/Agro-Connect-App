class ScheduleConfig {
  ScheduleConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'AGRO_API_BASE_URL',
    defaultValue: 'https://acro-connect.vercel.app',
  );

  static const String timezone = 'Asia/Kolkata';
  static const Duration requestTimeout = Duration(seconds: 15);
}
